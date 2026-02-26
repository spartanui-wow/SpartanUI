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
	self.DB = UF.CurrentSettings[unit]

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
			-- Hide frame background if frame is disabled
			if SUI.Handlers.BackgroundBorder then
				local frameName = self:GetName() or (self.unitOnCreate .. tostring(self))
				local instanceID = 'UnitFrame_' .. frameName
				SUI.Handlers.BackgroundBorder:SetVisible(instanceID, false)
			end
			return
		end

		-- Update frame background
		if SUI.Handlers.BackgroundBorder and self.DB.frameBackground then
			-- For group frames, use the actual frame name to create individual backgrounds
			local frameName = self:GetName() or (self.unitOnCreate .. tostring(self))
			local instanceID = 'UnitFrame_' .. frameName

			-- Deep copy settings so we don't mutate CurrentSettings
			local settings = SUI:CopyData({}, self.DB.frameBackground)

			if not SUI.Handlers.BackgroundBorder.instances[instanceID] then
				SUI.Handlers.BackgroundBorder:Create(self, instanceID, settings)
			else
				SUI.Handlers.BackgroundBorder:Update(instanceID, settings)
			end
			SUI.Handlers.BackgroundBorder:SetVisible(instanceID, true)
		end

		UF.Unit:Update(self)
		local elementsDB = self.DB.elements
		-- Check that its a frame
		-- Loop all elements and update their status
		for elementName, _ in pairs(self.elementList) do
			if not elementsDB[elementName] then
				SUI:Error('MISSING: ' .. elementName .. ' Type:' .. type(elementName))
			else
				self:ElementUpdate(elementName)
			end
		end

		for element, _ in pairs(self.elementList) do
			if self[element] and element ~= nil then
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
	self:SetScript('OnEnter', UnitFrame_OnEnter)
	self:SetScript('OnLeave', UnitFrame_OnLeave)
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
		-- Child group frames (partypet, partytarget) always need their holder created
		-- so template-spawned children can register. The Updater controls visibility.
		if settings.enabled or (config.isChild and config.IsGroup) then
			if config.IsGroup then
				local groupElement = UF.Unit:BuildGroup(frameName)
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
						else
							UnregisterAttributeDriver(firstElement, 'state-visibility')
							if VisibilityCheck(frameName) and UF.CurrentSettings[frameName].enabled then
								firstElement:Show()

								for _, f in pairs(groupFrame.frames) do
									if f.UpdateAll then
										f:UpdateAll()
									end
								end
							else
								firstElement:Hide()
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
					if groupFrame and groupFrame.header then
						local currentMode = groupFrame.header:GetAttribute('groupBy')
						groupFrame.header:SetAttribute('groupBy', currentMode)
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
