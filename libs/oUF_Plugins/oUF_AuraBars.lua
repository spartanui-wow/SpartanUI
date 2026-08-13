local _, ns = ...
local oUF = ns.oUF

local VISIBLE = 1
local HIDDEN = 0

local next = next
local wipe = wipe
local pcall = pcall
local unpack = unpack
local tinsert = tinsert

local GetTime = GetTime
local CreateFrame = CreateFrame
local UnitIsEnemy = UnitIsEnemy
local UnitReaction = UnitReaction
local GameTooltip = GameTooltip

local isRetail = WOW_PROJECT_ID == (WOW_PROJECT_MAINLINE or 1)
local canaccessvalue = canaccessvalue
local GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
local DoesAuraHaveExpirationTime = C_UnitAuras and C_UnitAuras.DoesAuraHaveExpirationTime

local LibDispel = LibStub('LibDispel-1.0')
local DebuffColors = LibDispel:GetDebuffTypeColor()

local YEAR, DAY, HOUR, MINUTE = 31557600, 86400, 3600, 60
local function FormatTime(sec)
	if sec < MINUTE then
		return '%.1fs', sec
	elseif sec < HOUR then
		return '%dm %ds', (sec % HOUR) / MINUTE, sec % MINUTE
	elseif sec < DAY then
		return '%dh %dm', (sec % DAY) / HOUR, (sec % HOUR) / MINUTE
	else
		return '%dd %dh', (sec % YEAR) / DAY, (sec % DAY) / HOUR
	end
end

---@param value any
---@return boolean
local function canAccess(value)
	if not canaccessvalue then
		return true
	end
	return canaccessvalue(value)
end

local function onEnter(self)
	if GameTooltip:IsForbidden() or not self:IsVisible() then
		return
	end

	local element = self.__owner
	GameTooltip:SetOwner(self, (element.__restricted and 'ANCHOR_CURSOR') or element.tooltipAnchor)

	if isRetail and self.auraInstanceID then
		if self.filter == 'HELPFUL' then
			GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID)
		else
			GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID)
		end
	else
		GameTooltip:SetUnitAura(self.unit, self.index, self.filter)
	end
end

local function onLeave()
	if GameTooltip:IsForbidden() then
		return
	end

	GameTooltip:Hide()
end

local function updateValue(bar, start)
	if isRetail and bar.auraDuration then
		local remain = bar.auraDuration:GetRemainingDuration()
		if remain then
			-- Pass secret-safe values directly to Blizzard widget APIs
			bar:SetMinMaxValues(0, bar.aura and bar.aura.duration or 1)
			bar:SetValue(remain)
			-- Time text: use remaining duration if accessible, otherwise hide
			if canAccess(remain) then
				bar.timeText:SetFormattedText(FormatTime(remain))
			else
				bar.timeText:SetText('')
			end
		end
	elseif bar.duration and bar.expiration then
		local remain = (bar.expiration - GetTime()) / (bar.modRate or 1)

		if start and bar.SetValue_ then
			bar:SetValue_(remain / bar.duration)
		else
			bar:SetValue(remain / bar.duration)
		end

		bar.timeText:SetFormattedText(FormatTime(remain))
	end
end

local function onUpdate(bar, elapsed)
	bar.elapsed = (bar.elapsed or 0) + elapsed

	if bar.elapsed > 0.01 then
		updateValue(bar)

		bar.elapsed = 0
	end
end

local function createAuraBar(element, index)
	local bar = CreateFrame('StatusBar', element:GetName() .. 'StatusBar' .. index, element)
	bar:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
	bar:SetMinMaxValues(0, 1)
	bar:SetScript('OnEnter', onEnter)
	bar:SetScript('OnLeave', onLeave)
	bar:EnableMouse(false)

	local spark = bar:CreateTexture(nil, 'OVERLAY', nil)
	spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
	spark:SetWidth(12)
	spark:SetBlendMode('ADD')
	spark:SetPoint('CENTER', bar:GetStatusBarTexture(), 'RIGHT')

	local icon = bar:CreateTexture(nil, 'ARTWORK')
	icon:SetPoint('RIGHT', bar, 'LEFT', -element.barSpacing, 0)
	icon:SetSize(element.height, element.height)

	local nameText = bar:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
	nameText:SetPoint('LEFT', bar, 'LEFT', 2, 0)

	local timeText = bar:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
	timeText:SetPoint('RIGHT', bar, 'RIGHT', -2, 0)

	bar.icon = icon
	bar.spark = spark
	bar.nameText = nameText
	bar.timeText = timeText
	bar.__owner = element

	if element.PostCreateBar then
		element:PostCreateBar(bar)
	end

	return bar
end

local function customFilter(element, unit, bar, auraData, name)
	if (element.onlyShowPlayer and bar.isPlayer) or (not element.onlyShowPlayer and name) then
		return true
	end
end

local function updateBar(element, bar)
	local count = bar.count
	if count and canAccess(count) and count > 1 then
		bar.nameText:SetFormattedText('[%d] %s', count, bar.spell)
	elseif isRetail and count and not canAccess(count) and bar.auraInstanceID and GetAuraApplicationDisplayCount then
		local displayCount = GetAuraApplicationDisplayCount(bar.unit, bar.auraInstanceID, 2, 999)
		if displayCount then
			bar.nameText:SetFormattedText('%s %s', displayCount, bar.spell)
		else
			bar.nameText:SetText(bar.spell)
		end
	else
		bar.nameText:SetText(bar.spell)
	end

	if not bar.noTime and element.sparkEnabled then
		bar.spark:Show()
	else
		bar.spark:Hide()
	end

	local r, g, b = 0.2, 0.6, 1
	local debuffType = bar.debuffType
	if element.buffColor then
		r, g, b = unpack(element.buffColor)
	end
	if bar.filter == 'HARMFUL' then
		if not debuffType or not canAccess(debuffType) or debuffType == '' then
			debuffType = 'none'
		end

		local color = DebuffColors[debuffType]
		if color then
			r, g, b = color.r, color.g, color.b
		end
	end

	bar.icon:SetTexture(bar.texture)
	bar.icon:SetSize(element.height, element.height)
	bar:SetStatusBarColor(r, g, b)
	bar:SetSize(element.width, element.height)
	bar:EnableMouse(not element.disableMouse)
	bar:SetID(bar.index)
	bar:Show()

	if element.PostUpdateBar then
		element:PostUpdateBar(bar.unit, bar, bar.index, bar.position, bar.duration, bar.expiration, debuffType, bar.isStealable)
	end
end

local function setupBar(
	element,
	bar,
	unit,
	index,
	filter,
	isDebuff,
	visible,
	offset,
	auraData,
	name,
	texture,
	count,
	debuffType,
	duration,
	expiration,
	source,
	isStealable,
	spellID,
	modRate,
	auraInstanceID
)
	local position = visible + offset + 1
	if not bar then
		bar = (element.CreateBar or createAuraBar)(element, position)
		tinsert(element, bar)
		element.createdBars = element.createdBars + 1
	end

	element.active[position] = bar

	bar.aura = auraData
	bar.unit = unit
	bar.count = count
	bar.index = index
	bar.caster = source
	bar.filter = filter
	bar.texture = texture
	bar.isDebuff = isDebuff
	bar.debuffType = debuffType
	bar.isStealable = isStealable
	bar.position = position
	bar.duration = duration
	bar.expiration = expiration
	bar.modRate = modRate
	bar.spellID = spellID
	bar.spell = name
	bar.auraInstanceID = auraInstanceID

	if canAccess(source) then
		bar.isPlayer = source == 'player' or source == 'vehicle'
	else
		bar.isPlayer = nil
	end

	if isRetail and auraInstanceID then
		local hasExpiration = DoesAuraHaveExpirationTime and DoesAuraHaveExpirationTime(unit, auraInstanceID)
		if canAccess(hasExpiration) and hasExpiration then
			bar.noTime = false
		elseif canAccess(hasExpiration) and not hasExpiration then
			bar.noTime = true
		else
			bar.noTime = false
		end
		bar.auraDuration = GetAuraDuration and GetAuraDuration(unit, auraInstanceID) or nil
	else
		if canAccess(duration) and canAccess(expiration) then
			bar.noTime = (duration == 0 and expiration == 0)
		else
			bar.noTime = true
		end
		bar.auraDuration = nil
	end

	local show = (element.CustomFilter or customFilter)(element, unit, bar, auraData, name)

	updateBar(element, bar)

	if bar.noTime then
		bar:SetScript('OnUpdate', nil)
	else
		updateValue(bar, true)
		bar:SetScript('OnUpdate', onUpdate)
	end

	return show and VISIBLE or HIDDEN
end

local function filterBarsRetail(element, unit, filter, limit, isDebuff, offset, dontHide)
	if not offset then
		offset = 0
	end
	local visible = 0
	local hidden = 0

	-- GetAuraSlots errors outright once auras are secret - it is not a value
	-- that can be checked with canaccessvalue, the call itself is refused. The
	-- bars simply have nothing to show in that case.
	local ok, slots = pcall(function()
		return { GetAuraSlots(unit, filter) }
	end)
	if not ok then
		-- Hide whatever is still on screen, exactly as the normal path does
		-- when it runs out of auras, or the last visible bars would stay up.
		if not dontHide then
			for i = offset + 1, #element do
				element[i]:Hide()
			end
		end

		return 0, 0
	end

	local index = 0
	for i = 2, #slots do
		if visible >= limit then
			break
		end

		local data = GetAuraDataBySlot(unit, slots[i])
		if data then
			index = index + 1
			local position = visible + offset + 1
			local bar = element[position]

			local result = setupBar(
				element,
				bar,
				unit,
				index,
				filter,
				isDebuff,
				visible,
				offset,
				data,
				data.name,
				data.icon,
				data.applications,
				data.dispelName,
				data.duration,
				data.expirationTime,
				data.sourceUnit,
				data.isStealable,
				data.spellId,
				data.timeMod,
				data.auraInstanceID
			)

			if result == VISIBLE then
				visible = visible + 1
			elseif result == HIDDEN then
				hidden = hidden + 1
			end
		end
	end

	if not dontHide then
		for i = visible + offset + 1, #element do
			element[i]:Hide()
		end
	end

	return visible, hidden
end

local function filterBarsClassic(element, unit, filter, limit, isDebuff, offset, dontHide)
	if not offset then
		offset = 0
	end
	local index = 1
	local visible = 0
	local hidden = 0

	while visible < limit do
		local name, texture, count, debuffType, duration, expiration, source, isStealable, nameplateShowPersonal, spellID, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, modRate =
			UnitAura(unit, index, filter)

		if not name then
			break
		end

		local position = visible + offset + 1
		local bar = element[position]

		local result = setupBar(element, bar, unit, index, filter, isDebuff, visible, offset, nil, name, texture, count, debuffType, duration, expiration, source, isStealable, spellID, modRate, nil)

		if result == VISIBLE then
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

local filterBars = isRetail and filterBarsRetail or filterBarsClassic

local function SetPosition(element, from, to)
	local height = element.height
	local spacing = element.spacing
	local anchor = element.initialAnchor
	local barSpacing = element.barSpacing
	local growth = element.growth == 'DOWN' and -1 or 1

	for i = from, to do
		local bar = element.active[i]
		if not bar then
			break
		end

		bar:ClearAllPoints()
		bar:SetPoint(anchor, element, anchor, barSpacing, (i == 1 and 0) or (growth * ((i - 1) * (height + spacing))))

		if bar.noTime then
			bar:SetValue(1)
			bar.timeText:SetText('')
		end
	end
end

local function UpdateAuras(self, event, unit, updateInfo)
	if not unit or self.unit ~= unit then
		return
	end

	local element = self.AuraBars
	if not element then
		return
	end

	if element.PreUpdate then
		element:PreUpdate(unit)
	end

	wipe(element.active)

	local isEnemy = UnitIsEnemy(unit, 'player')
	local reaction = UnitReaction(unit, 'player')
	local filter = (not isEnemy and (not reaction or reaction > 4) and (element.friendlyAuraType or 'HELPFUL')) or element.enemyAuraType or 'HARMFUL'
	local visibleAuras = filterBars(element, unit, filter, element.maxBars, filter == 'HARMFUL', 0)

	element.visibleAuras = visibleAuras

	local fromRange, toRange
	if element.PreSetPosition then
		fromRange, toRange = element:PreSetPosition(element.maxBars)
	end

	if fromRange or element.createdBars > element.anchoredBars then
		(element.SetPosition or SetPosition)(element, fromRange or element.anchoredBars + 1, toRange or element.createdBars)
		element.anchoredBars = element.createdBars
	end

	if element.PostUpdate then
		element:PostUpdate(unit)
	end
end

local function Update(self, event, unit)
	if self.unit ~= unit then
		return
	end

	UpdateAuras(self, event, unit)

	-- Assume no event means someone wants to re-anchor things. This is usually
	-- done by UpdateAllElements and :ForceUpdate.
	if event == 'ForceUpdate' or not event then
		local element = self.AuraBars
		if element then
			(element.SetPosition or SetPosition)(element, 1, element.createdBars)
		end
	end
end

local function ForceUpdate(element)
	return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self)
	local element = self.AuraBars

	if element then
		self:RegisterEvent('UNIT_AURA', UpdateAuras)

		element.__owner = self
		element.ForceUpdate = ForceUpdate
		element.active = {}

		element.anchoredBars = 0
		element.createdBars = element.createdBars or 0
		element.width = element.width or 240
		element.height = element.height or 12
		element.sparkEnabled = element.sparkEnabled or true
		element.spacing = element.spacing or 2
		element.initialAnchor = element.initialAnchor or 'BOTTOMLEFT'
		element.growth = element.growth or 'UP'
		element.maxBars = element.maxBars or 32
		element.barSpacing = element.barSpacing or 2
		element.tooltipAnchor = element.tooltipAnchor or 'ANCHOR_BOTTOMRIGHT'

		-- Avoid parenting GameTooltip to frames with anchoring restrictions
		element.__restricted = not pcall(self.GetCenter, self)

		element:Show()

		return true
	end
end

local function Disable(self)
	local element = self.AuraBars

	if element then
		self:UnregisterEvent('UNIT_AURA', UpdateAuras)

		element:Hide()
	end
end

oUF:AddElement('AuraBars', Update, Enable, Disable)
