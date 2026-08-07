local _G, SUI = _G, SUI
local UF = SUI.UF ---@class SUI.UF
----------------------------------------------------------------------------------------------------

function UF:CalculateHeight(frameName)
	local elements = UF.CurrentSettings[frameName].elements
	local FrameHeight = 0
	if elements.Castbar.enabled then
		FrameHeight = FrameHeight + elements.Castbar.height
	end
	if elements.Health.enabled then
		FrameHeight = FrameHeight + elements.Health.height
	end
	if elements.Power.enabled then
		FrameHeight = FrameHeight + elements.Power.height
	end

	if UF.BuildDebug then
		UF:debug(
			'CalculateHeight('
				.. frameName
				.. '): Castbar='
				.. (elements.Castbar.enabled and tostring(elements.Castbar.height) or 'OFF')
				.. ' Health='
				.. (elements.Health.enabled and tostring(elements.Health.height) or 'OFF')
				.. ' Power='
				.. (elements.Power.enabled and tostring(elements.Power.height) or 'OFF')
				.. ' => '
				.. FrameHeight
		)
	end

	return FrameHeight
end

---Show the unit tooltip on hover.
---
---Blizzard's UnitFrame_OnEnter hands self.unit straight to GameTooltip:SetUnit,
---which errors when the frame has no unit yet - group frames are built before
---the secure header assigns one. The unit can also be a secret value, which
---SetUnit will not take either.
---@param frame table
function UF:UnitFrame_OnEnter(frame)
	frame = frame or self

	if GameTooltip:IsForbidden() then
		frame.UpdateTooltip = nil
		return
	end

	GameTooltip_SetDefaultAnchor(GameTooltip, frame)

	local unit = frame.unit
	if unit and SUI.BlizzAPI.canaccessvalue(unit) and UnitExists(unit) then
		GameTooltip:SetUnit(unit)
		frame.UpdateTooltip = UF.UnitFrame_OnEnter
	else
		frame.UpdateTooltip = nil
		GameTooltip:Hide()
	end
end

---@param frame table
function UF:UnitFrame_OnLeave(frame)
	frame = frame or self
	frame.UpdateTooltip = nil

	if not GameTooltip:IsForbidden() then
		GameTooltip:Hide()
	end
end

local function CreateUnitFrame(self, unit)
	local frameName = self:GetName() or 'Unknown'
	if UF.BuildDebug then
		UF:debug('CreateUnitFrame ENTRY - Frame: ' .. frameName .. ', Unit: ' .. tostring(unit))
	end

	if unit ~= 'raid' and unit ~= 'party' then
		if SUI_FramesAnchor:GetParent() == UIParent then
			self:SetParent(UIParent)
		else
			self:SetParent(SUI_FramesAnchor)
		end
	end
	-- boss1..boss8 and arena1..arena5 spawn Blizzard target children (boss1target, etc.)
	-- via SecureUnitButtonTemplate. These numbered compound children are not SUI frames
	-- and must not be styled -- WoW 12.0 rejects compound tokens in all Unit APIs.
	if string.match(unit, '%d+target$') then
		return
	end
	-- boss1..boss8 and arena1..arena5 all share the boss/arena settings.
	-- bosstarget and arenatarget are registered units with their own settings, skip remapping them.
	if string.match(unit, 'boss%d') then
		unit = 'boss'
	elseif string.match(unit, 'arena%d') then
		unit = 'arena'
	end

	-- Pinned resolution: the pinned header sets showRaid/showParty/showPlayer all true,
	-- so oUF guesses unit='raid' (or 'party'/'player') for its children. There is no 'raid'
	-- settings key (only raid10/raid25/raid40), so use the pinned config for these children.
	if string.match(frameName, '^SUI_UF_pinned_') then
		unit = 'pinned'
	end

	-- Raid tier resolution: oUF passes unit='raid' for all SecureGroupHeaders with showRaid.
	-- Extract the actual tier (raid10/raid25/raid40) from the header frame name.
	-- Supports both single-header (SUI_UF_raid40_Header) and multi-header (SUI_UF_raid40_G3_Header) names.
	if unit == 'raid' then
		local tierName = string.match(frameName, 'SUI_UF_(raid%d+)_')
		if tierName and UF.CurrentSettings[tierName] then
			unit = tierName
		end
	end
	self.DB = UF.CurrentSettings[unit]

	-- Guard against an unresolved unit key. Without settings we cannot size or style the
	-- frame, so bail out instead of erroring on every secure header child.
	if not self.DB then
		UF:debug('CreateUnitFrame: no settings for unit "' .. tostring(unit) .. '" (frame ' .. frameName .. '), skipping')
		return
	end

	if self.isChild then
		self.childType = 'pet'
		if self == _G[self:GetName() .. 'Target'] then
			self.childType = 'target'
		end
	end

	self.unitOnCreate = unit
	self.elementList = {}

	-- Build a function that updates the size of the frame and sizes of elements
	local function UpdateSize()
		if not InCombatLockdown() then
			if self.scale then
				self:scale(self.DB.scale, true)
			else
				self:SetScale(self.DB.scale)
			end
			self:SetSize(self.DB.width, UF:CalculateHeight(unit))
		end
	end

	local function UpdateAll()
		self.DB = UF.CurrentSettings[self.unitOnCreate]
		UpdateSize()

		-- Apply custom position for partypet child frames
		if self.childType == 'pet' and not InCombatLockdown() then
			local posX = self.DB.positionX or 0
			local posY = self.DB.positionY or 1
			local posPoint = self.DB.positionPoint or 'BOTTOMRIGHT'
			local posRelPoint = self.DB.positionRelativePoint or 'BOTTOMLEFT'
			self:ClearAllPoints()
			self:SetPoint(posPoint, self:GetParent(), posRelPoint, posX, posY)
		end

		if not self.DB or not self.DB.enabled then
			self:Disable()
			return
		end

		UF.Unit:Update(self)
		local elementsDB = self.DB.elements
		for element, _ in pairs(self.elementList) do
			if not elementsDB[element] then
				SUI:Error('MISSING: ' .. element .. ' Type:' .. type(element))
			elseif self[element] and element ~= nil then
				-- oUF Update (event/updater state)
				if elementsDB[element].enabled then
					self:EnableElement(element)
				else
					self:DisableElement(element)
				end
				--Background
				if self[element].bg then
					if elementsDB[element].bg.enabled then
						self[element].bg:Show()
						if elementsDB[element].bg.color and type(elementsDB[element].bg.color) == 'table' then
							self[element].bg:SetVertexColor(unpack(elementsDB[element].bg.color))
						end
					else
						self[element].bg:Hide()
					end
				end
				-- SUI Update (size, position, etc)
				self:ElementUpdate(element)
			end
		end

		-- Tell everything to update to get current data.
		-- Skip if the unit doesn't exist yet -- WoW 12.0 errors on all Unit APIs
		-- (UnitHealth, UnitPower, UnitGetDetailedHealPrediction, etc.) for compound
		-- tokens like targettarget/focustarget when no such unit is currently present.
		if not self.unit or UnitExists(self.unit) then
			self:UpdateAllElements('OnUpdate')
			self:UpdateTags()
		end
	end

	---@param frame table
	---@param elementName SUI.UF.Elements.list
	local function ElementUpdate(frame, elementName)
		if not frame[elementName] then
			return
		end
		local data = self.DB.elements[elementName]
		local element = frame[elementName]
		element.DB = data

		if data.enabled and frame.IsBuilt then
			frame:EnableElement(elementName)
		else
			frame:DisableElement(elementName)
		end

		-- Call the elements update function
		UF.Elements:Update(frame, elementName)

		if UF.Elements:GetConfig(elementName).config.NoBulkUpdate then
			return
		end

		if not data then
			SUI:Error('NO SETTINGS FOR "' .. unit .. '" element: ' .. elementName)
			return
		end

		-- Setup the Alpha scape and position
		element:SetAlpha(data.alpha)
		element:SetScale(data.scale)

		-- Positioning
		element:ClearAllPoints()
		if data.points then
			if type(data.points) == 'string' then
				element:SetAllPoints(frame[data.points])
			elseif data.points and type(data.points) == 'table' then
				for _, key in pairs(data.points) do
					if key.relativeTo == 'Frame' then
						element:SetPoint(key.anchor, frame, key.anchor, key.x, key.y)
					else
						element:SetPoint(key.anchor, frame[key.relativeTo], key.anchor, key.x, key.y)
					end
				end
			else
				element:SetAllPoints(frame)
			end
		elseif data.position.anchor then
			-- Check for smart positioning (dynamic relative positioning)
			local targetElement = nil
			local useSmartPosition = data.position.smartPosition and data.position.smartPosition.enabled

			if useSmartPosition then
				-- Smart positioning: anchor to another element if it exists and is enabled
				local smartTarget = data.position.smartPosition.anchorTo
				if smartTarget and frame[smartTarget] and frame[smartTarget].DB and frame[smartTarget].DB.enabled then
					targetElement = frame[smartTarget]
				end
			end

			-- Apply positioning
			if targetElement then
				-- Smart positioning: anchor to target element
				element:SetPoint(data.position.anchor, targetElement, data.position.relativePoint or data.position.anchor, data.position.x or 0, data.position.y or 0)
			elseif data.position.relativeTo == 'Frame' then
				-- Standard positioning: anchor to frame
				element:SetPoint(data.position.anchor, frame, data.position.relativePoint or data.position.anchor, data.position.x, data.position.y)
			else
				-- Standard positioning: anchor to specific element
				element:SetPoint(data.position.anchor, frame[data.position.relativeTo], data.position.relativePoint or data.position.anchor, data.position.x, data.position.y)
			end
		end

		--Size it if we have a size change function for the element
		if element.SizeChange then
			element:SizeChange()
		elseif data.size then
			element:SetSize(data.size, data.size)
		else
			element:SetSize(data.width or frame:GetWidth(), data.height or frame:GetHeight())
		end

		-- Call the elements update function.
		-- Skip if the unit doesn't exist yet -- WoW 12.0 rejects compound tokens
		-- (targettarget, focustarget, etc.) in all Unit APIs when no unit is present.
		if frame[elementName] and data.enabled and frame[elementName].ForceUpdate then
			if not frame.unit or UnitExists(frame.unit) then
				frame[elementName].ForceUpdate(element)
			end
		end
	end

	self.raised = CreateFrame('Frame', nil, self)
	local level = self:GetFrameLevel() + 100
	self.raised:SetFrameLevel(level)
	self.raised.__owner = self

	self.UpdateAll = UpdateAll
	self.ElementUpdate = ElementUpdate

	UpdateSize()

	local elementDB = self.DB.elements
	self.elementDB = elementDB

	UF.Unit:BuildFrame(unit, self)

	for elementName, _ in pairs(self.elementList) do
		if elementDB[elementName] then
			ElementUpdate(self, elementName)
		end
	end

	-- Setup the frame's Right click menu.
	self:RegisterForClicks('AnyDown')
	if not InCombatLockdown() then
		self:EnableMouse(true)
	end
	self:SetClampedToScreen(true)
	--Setup unitframes tooltip hook
	self:SetScript('OnEnter', UF.UnitFrame_OnEnter)
	self:SetScript('OnLeave', UF.UnitFrame_OnLeave)
	self.IsBuilt = true

	if not self.DB.enabled then
		self:Disable()
	end

	return self
end

local function VisibilityCheck(group)
	if UF.CurrentSettings[group].showParty and (IsInGroup() and not IsInRaid()) then
		return true
	end
	if UF.CurrentSettings[group].showRaid and IsInRaid() then
		return true
	end
	if UF.CurrentSettings[group].showSolo and not (IsInGroup() or IsInRaid()) then
		return true
	end

	return false
end

-- Difficulty category mapping: difficultyID -> category key
-- See https://warcraft.wiki.gg/wiki/DifficultyID for full list
local difficultyCategories = {
	-- Normal Dungeon
	[1] = 'normalDungeon',
	-- Heroic Dungeon
	[2] = 'heroicDungeon',
	-- Normal Raid (10/25)
	[3] = 'normalRaid',
	[4] = 'normalRaid',
	[14] = 'normalRaid',
	-- Heroic Raid (10/25)
	[5] = 'heroicRaid',
	[6] = 'heroicRaid',
	[15] = 'heroicRaid',
	-- Mythic Dungeon
	[23] = 'mythicDungeon',
	-- Mythic+ Keystone
	[8] = 'mythicPlus',
	-- Mythic Raid
	[16] = 'mythicRaid',
	-- LFR
	[7] = 'lfr',
	[17] = 'lfr',
	-- Timewalking
	[24] = 'timewalking',
	[33] = 'timewalking',
	-- Follower Dungeon
	[205] = 'followerDungeon',
}

local function DifficultyVisibilityCheck(group)
	local dv = UF.CurrentSettings[group].difficultyVisibility
	if not dv or not dv.enabled then
		return nil
	end

	local inInstance, instanceType = IsInInstance()
	if not inInstance or instanceType == 'none' then
		if dv.openWorld == false then
			return false
		end
		return nil
	end

	local _, _, difficultyID = GetInstanceInfo()
	local category = difficultyCategories[difficultyID]

	if category and dv[category] ~= nil then
		return dv[category]
	end

	return nil
end

function UF:SpawnFrames()
	SUIUF:RegisterStyle('SpartanUI_UnitFrames', CreateUnitFrame)
	SUIUF:SetActiveStyle('SpartanUI_UnitFrames')

	local function GroupEnableElement(groupFrame, elementName)
		for _, f in ipairs(groupFrame.frames) do
			if f.EnableElement then
				f:EnableElement(elementName)
			end
		end
	end
	local function GroupDisableElement(groupFrame, elementName)
		for _, f in ipairs(groupFrame.frames) do
			if f.DisableElement then
				f:DisableElement(elementName)
			end
		end
	end
	local function GroupFrameElementUpdate(groupFrame, elementName)
		for _, f in ipairs(groupFrame.frames) do
			if f.ElementUpdate then
				f:ElementUpdate(elementName)
			end
		end
	end
	local function GroupFrameEnable(groupFrame)
		groupFrame:UpdateAll()
		for _, f in ipairs(groupFrame.frames) do
			if f.Enable then
				f:Enable()
			end
		end
	end
	local function GroupFrameDisable(groupFrame)
		groupFrame:UpdateAll()
		for _, f in ipairs(groupFrame.frames) do
			if f.Disable then
				f:Disable()
			end
		end
	end

	-- Spawn all main frames
	for frameName, config in pairs(UF.Unit:GetFrameList()) do
		local settings = UF.CurrentSettings[frameName]
		-- Always spawn: child group frames (template children need a holder) and
		-- raid tiers (enable/disable at runtime without reload). Updater controls visibility.
		local alwaysSpawn = (config.isChild and config.IsGroup) or frameName:match('^raid%d+$')
		if settings.enabled or alwaysSpawn then
			if config.IsGroup then
				local groupElement = UF.Unit:BuildGroup(frameName)

				-- Collect current active headers dynamically (supports runtime mode switching)
				local function GetActiveHeaders()
					local headers = {}
					if groupElement.headers then
						for _, h in ipairs(groupElement.headers) do
							headers[#headers + 1] = h
						end
					elseif groupElement.header then
						headers[1] = groupElement.header
					end
					return headers
				end

				local firstElement = groupElement.header or groupElement.frames[1] or groupElement
				if firstElement then
					local isChildGroup = config.isChild and config.IsGroup
					local function GroupFrameUpdateAll(groupFrame)
						if isChildGroup then
							-- Child groups (partypet, partytarget) are managed by header template.
							-- Always update children - the Updater handles individual visibility.
							for _, f in pairs(groupFrame.frames) do
								if f.UpdateAll then
									f:UpdateAll()
								end
							end
						elseif config.useUnitWatch then
							-- Boss/arena: visibility managed by oUF RegisterUnitWatch.
							-- Do NOT touch attribute drivers or call Show/Hide.
							for _, f in pairs(groupFrame.frames) do
								if f.UpdateAll and f.unit and UnitExists(f.unit) then
									f:UpdateAll()
								end
							end
						else
							-- Apply visibility to all active headers (read dynamically for runtime mode switching)
							local currentHeaders = GetActiveHeaders()
							for _, headerElem in ipairs(currentHeaders) do
								UnregisterAttributeDriver(headerElem, 'state-visibility')
							end

							local customVisibility = UF.CurrentSettings[frameName].customVisibility
							if customVisibility and customVisibility ~= '' and UF.CurrentSettings[frameName].enabled then
								for _, headerElem in ipairs(currentHeaders) do
									RegisterStateDriver(headerElem, 'state-visibility', customVisibility)
								end
								for _, f in pairs(groupFrame.frames) do
									if f.UpdateAll then
										f:UpdateAll()
									end
								end
							else
								-- Check per-difficulty visibility override
								local diffCheck = DifficultyVisibilityCheck(frameName)
								local shouldShow
								if diffCheck ~= nil then
									shouldShow = diffCheck and UF.CurrentSettings[frameName].enabled
								else
									shouldShow = VisibilityCheck(frameName) and UF.CurrentSettings[frameName].enabled
								end

								if shouldShow then
									for _, headerElem in ipairs(currentHeaders) do
										headerElem:Show()
									end
									for _, f in pairs(groupFrame.frames) do
										if f.UpdateAll then
											f:UpdateAll()
										end
									end
								else
									for _, headerElem in ipairs(currentHeaders) do
										headerElem:Hide()
									end
								end
							end
						end
					end

					groupElement.UpdateAll = GroupFrameUpdateAll
					groupElement.ElementUpdate = GroupFrameElementUpdate
					groupElement.Enable = GroupFrameEnable
					groupElement.Disable = GroupFrameDisable
					groupElement.EnableElement = GroupEnableElement
					groupElement.DisableElement = GroupDisableElement
				end
				UF.Unit[frameName] = groupElement
			else
				UF.Unit[frameName] = SUIUF:Spawn(frameName, 'SUI_UF_' .. frameName)
			end

			-- Trigger update
			UF.Unit[frameName]:UpdateAll()
		end
	end

	local pendingHeaderUpdates = {}

	local function GroupWatcher(event)
		-- Removed verbose debug logging - was causing log spam
		if not InCombatLockdown() then
			-- Update 1 second after login
			if event == 'PLAYER_ENTERING_WORLD' or event == 'GROUP_JOINED' then
				UF:ScheduleTimer(GroupWatcher, 1)
				return
			end

			UF:UpdateGroupFrames(event)

			-- Process any pending header updates that were deferred during combat
			if next(pendingHeaderUpdates) then
				for frameName, _ in pairs(pendingHeaderUpdates) do
					local groupFrame = UF.Unit:Get(frameName)
					if groupFrame then
						-- Handle both single and multi-header modes
						if groupFrame.headers then
							for _, header in ipairs(groupFrame.headers) do
								local currentMode = header:GetAttribute('groupBy')
								header:SetAttribute('groupBy', currentMode)
							end
						elseif groupFrame.header then
							local currentMode = groupFrame.header:GetAttribute('groupBy')
							groupFrame.header:SetAttribute('groupBy', currentMode)
						end
					end
				end
				wipe(pendingHeaderUpdates)
			end
		else
			-- During combat, mark headers as needing update
			for frameName, _ in pairs(UF.Unit:GetFrameList(true)) do
				pendingHeaderUpdates[frameName] = true
			end
		end
	end
	UF:RegisterEvent('GROUP_ROSTER_UPDATE', GroupWatcher)
	UF:RegisterEvent('GROUP_JOINED', GroupWatcher)
	UF:RegisterEvent('PLAYER_ENTERING_WORLD', GroupWatcher)
	UF:RegisterEvent('ZONE_CHANGED', GroupWatcher)
	UF:RegisterEvent('READY_CHECK', GroupWatcher)
	UF:RegisterEvent('PARTY_MEMBER_ENABLE', GroupWatcher)
	UF:RegisterEvent('PLAYER_LOGIN', GroupWatcher)
	UF:RegisterEvent('RAID_ROSTER_UPDATE', GroupWatcher)
	UF:RegisterEvent('PARTY_LEADER_CHANGED', GroupWatcher)
	UF:RegisterEvent('PLAYER_REGEN_ENABLED', GroupWatcher)
	UF:RegisterEvent('ZONE_CHANGED_NEW_AREA', GroupWatcher)
	UF:RegisterEvent('PLAYER_DIFFICULTY_CHANGED', GroupWatcher)
end

function UF:UpdateAll(event, ...)
	for frameName, config in pairs(UF.Unit:GetBuiltFrameList()) do
		local frame = UF.Unit:Get(frameName)
		if frame and frame.UpdateAll then
			frame:UpdateAll()
		elseif not config.isChild then
			SUI:Error('Unable to find updater for ' .. frameName, 'Unit Frames')
		end
	end

	UF:UpdateGroupFrames()
end

function UF:UpdateGroupFrames(event, ...)
	for frameName, _ in pairs(UF.Unit:GetFrameList(true)) do
		local frame = UF.Unit:Get(frameName)
		if frame then
			frame:UpdateAll()
		end
	end
end
