---@class SUI.UF
local UF = SUI.UF

local PreviewFrame = {}
UF.PreviewFrame = PreviewFrame

-- Storage for active preview frames
local previews = {} -- previews[frameName] = { frames = {}, showing = false }

-- Elements to build on preview frames (visual-only elements)
-- Order matches the real builder order (player.lua) so relative positioning works
local PREVIEW_ELEMENTS = {
	'FrameBackground',
	'Name',
	'Health',
	'Castbar',
	'Power',
}

----------------------------------------------------------------------------------------------------
-- Mock Tag Interpreter
----------------------------------------------------------------------------------------------------

---Interpret an oUF tag string and apply mock text to the fontstring
---@param fs FontString
---@param tagString string
---@param mockData table
local function ApplyMockTag(fs, tagString, mockData)
	if not fs or not mockData then
		return
	end

	local text = ''
	local mockCur, mockMax

	-- Health-related tags
	if tagString:find('curhp') or tagString:find('SUIHealth') or tagString:find('SUICurHP') then
		mockMax = 100
		mockCur = math.floor(mockData.healthPct * mockMax)
		if tagString:find('max') or tagString:find('/') or tagString:find('$>') then
			text = mockCur .. ' / ' .. mockMax
		else
			text = tostring(mockCur)
		end
	elseif tagString:find('perhp') then
		text = math.floor(mockData.healthPct * 100) .. '%'

	-- Power-related tags
	elseif tagString:find('curpp') or tagString:find('SUIPower') or tagString:find('SUICurPP') then
		mockMax = 100
		mockCur = math.floor(mockData.powerPct * mockMax)
		if tagString:find('max') or tagString:find('/') or tagString:find('$>') then
			text = mockCur .. ' / ' .. mockMax
		else
			text = tostring(mockCur)
		end
	elseif tagString:find('perpp') then
		text = math.floor(mockData.powerPct * 100) .. '%'

	-- Name tags (with class color support)
	elseif tagString:find('name') then
		local classColor = (RAID_CLASS_COLORS or {})[mockData.class]
		if tagString:find('ColorClass') or tagString:find('raidcolor') or tagString:find('classcolor') then
			if classColor then
				text = ('|cff%02x%02x%02x%s|r'):format(classColor.r * 255, classColor.g * 255, classColor.b * 255, mockData.name)
			else
				text = mockData.name
			end
		else
			text = mockData.name
		end

	-- Level tags
	elseif tagString:find('level') or tagString:find('smartlevel') then
		text = '70'

	-- Spell/cast tags
	elseif tagString:find('spell') or tagString:find('cast') then
		text = mockData.mockCast and mockData.mockCast.name or ''

	-- Dead/offline tags
	elseif tagString:find('dead') or tagString:find('Dead') then
		text = ''

	-- Difficulty tags
	elseif tagString:find('difficulty') then
		text = ''
	end

	fs:SetText(text)
end

----------------------------------------------------------------------------------------------------
-- Mock Data Application
----------------------------------------------------------------------------------------------------

---Hide all health prediction sub-bars that oUF normally manages
---@param preview table
local function HideHealthPredictionBars(preview)
	-- Retail hangs these off Health, Classic keeps them in a
	-- HealthPrediction table. Cover both.
	local health = preview.Health
	local pred = preview.HealthPrediction

	local bars = {
		health and health.HealingAll or (pred and pred.healingAll),
		health and health.HealingPlayer or (pred and pred.healingPlayer),
		health and health.HealingOther or (pred and pred.healingOther),
		health and health.DamageAbsorb or (pred and pred.damageAbsorb),
		health and health.HealAbsorb or (pred and pred.healAbsorb),
		health and health.OverDamageAbsorbIndicator or (pred and pred.overDamageAbsorbIndicator),
		health and health.OverHealAbsorbIndicator or (pred and pred.overHealAbsorbIndicator),
	}

	for _, bar in pairs(bars) do
		bar:Hide()
	end
end

---Apply mock values to built elements (health/power bars, castbar, colors)
---@param preview table
local function ApplyMockData(preview)
	local mock = preview.mockData
	if not mock then
		return
	end

	-- Health bar: set mock value and class color
	if preview.Health then
		preview.Health:SetMinMaxValues(0, 100)
		preview.Health:SetValue(math.floor(mock.healthPct * 100))

		local classColor = (RAID_CLASS_COLORS or {})[mock.class]
		if classColor then
			preview.Health:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
		end

		-- Hide cutaway ghost bar
		if preview.Health.tempLoss then
			preview.Health.tempLoss:Hide()
		end

		-- Hide all heal prediction / absorb sub-bars (oUF manages these on real frames)
		HideHealthPredictionBars(preview)
	end

	-- Power bar: set mock value and power type color
	if preview.Power then
		preview.Power:SetMinMaxValues(0, 100)
		preview.Power:SetValue(math.floor(mock.powerPct * 100))
		preview.Power:Show()

		local powerColor = preview.colors and preview.colors.power and preview.colors.power[mock.powerToken]
		if powerColor then
			if powerColor.GetRGB then
				preview.Power:SetStatusBarColor(powerColor:GetRGB())
			elseif powerColor.r then
				preview.Power:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
			end
		end

		-- Hide cost prediction
		if preview.Power.CostPrediction then
			preview.Power.CostPrediction:Hide()
		end
	end

	-- Castbar: set mock cast progress
	if preview.Castbar then
		local castDB = preview.elementDB and preview.elementDB.Castbar
		if castDB and castDB.enabled and mock.mockCast then
			local elapsed = mock.mockCast.duration * (0.3 + ((mock.healthPct * 100) % 40) / 100)
			preview.Castbar:SetMinMaxValues(0, mock.mockCast.duration)
			preview.Castbar:SetValue(elapsed)
			preview.Castbar:Show()

			if preview.Castbar.Text then
				preview.Castbar.Text:SetText(mock.mockCast.name)
			end
			if preview.Castbar.Time then
				preview.Castbar.Time:SetFormattedText('%.1f', mock.mockCast.duration - elapsed)
			end
			if preview.Castbar.Icon then
				preview.Castbar.Icon:SetTexture(mock.mockCast.icon)
			end

			if castDB.customColors and castDB.customColors.useCustom then
				preview.Castbar:SetStatusBarColor(unpack(castDB.customColors.barColor))
			else
				preview.Castbar:SetStatusBarColor(1, 0.7, 0)
			end

			-- Hide elements that only matter during real casts
			if preview.Castbar.Shield then
				preview.Castbar.Shield:SetAlpha(0)
			end
			if preview.Castbar.InterruptibleOverlay then
				preview.Castbar.InterruptibleOverlay:SetAlpha(0)
			end
			if preview.Castbar.SafeZone then
				preview.Castbar.SafeZone:Hide()
			end
		else
			preview.Castbar:Hide()
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Element Positioning (replicates SpawnFrames.lua ElementUpdate logic)
----------------------------------------------------------------------------------------------------

---Apply element positioning from settings (mirrors SpawnFrames.lua lines 155-244)
---@param preview table
---@param elementName string
---@param data table
local function ApplyElementPosition(preview, elementName, data)
	local element = preview[elementName]
	if not element then
		return
	end

	local config = UF.Elements:GetConfig(elementName)
	if config.config.NoBulkUpdate then
		return
	end

	if not data then
		return
	end

	element:SetAlpha(data.alpha or 1)
	element:SetScale(data.scale or 1)

	element:ClearAllPoints()
	if data.points then
		if type(data.points) == 'string' then
			element:SetAllPoints(preview[data.points] or preview)
		elseif type(data.points) == 'table' then
			for _, key in pairs(data.points) do
				if key.relativeTo == 'Frame' then
					element:SetPoint(key.anchor, preview, key.anchor, key.x, key.y)
				else
					element:SetPoint(key.anchor, preview[key.relativeTo] or preview, key.anchor, key.x, key.y)
				end
			end
		else
			element:SetAllPoints(preview)
		end
	elseif data.position and data.position.anchor then
		local targetElement = nil
		local useSmartPosition = data.position.smartPosition and data.position.smartPosition.enabled

		if useSmartPosition then
			local smartTarget = data.position.smartPosition.anchorTo
			if smartTarget and preview[smartTarget] and preview[smartTarget].DB and preview[smartTarget].DB.enabled then
				targetElement = preview[smartTarget]
			end
		end

		if targetElement then
			element:SetPoint(data.position.anchor, targetElement, data.position.relativePoint or data.position.anchor, data.position.x or 0, data.position.y or 0)
		elseif data.position.relativeTo == 'Frame' then
			element:SetPoint(data.position.anchor, preview, data.position.relativePoint or data.position.anchor, data.position.x or 0, data.position.y or 0)
		else
			element:SetPoint(data.position.anchor, preview[data.position.relativeTo] or preview, data.position.relativePoint or data.position.anchor, data.position.x or 0, data.position.y or 0)
		end
	end

	if element.SizeChange then
		element:SizeChange()
	elseif data.size then
		element:SetSize(data.size, data.size)
	else
		element:SetSize(data.width or preview:GetWidth(), data.height or preview:GetHeight())
	end
end

----------------------------------------------------------------------------------------------------
-- Preview Frame Construction
----------------------------------------------------------------------------------------------------

---Clear all children and element references from a preview frame for rebuild
---@param preview table
local function CleanPreviewFrame(preview)
	-- Hide and detach all child frames except the raised frame
	local children = { preview:GetChildren() }
	for _, child in ipairs(children) do
		if child ~= preview.raised then
			child:Hide()
			child:ClearAllPoints()
			child:SetParent(nil)
		end
	end

	-- Clear raised frame children
	local raisedChildren = { preview.raised:GetChildren() }
	for _, child in ipairs(raisedChildren) do
		child:Hide()
		child:ClearAllPoints()
		child:SetParent(nil)
	end

	-- Hide and detach regions on the raised frame (fontstrings, textures)
	local raisedRegions = { preview.raised:GetRegions() }
	for _, region in ipairs(raisedRegions) do
		region:Hide()
		region:ClearAllPoints()
		region:SetParent(nil)
	end

	-- Clean up BackgroundBorder instance if it exists
	local bgInstanceID = preview._bgInstanceID
	if bgInstanceID and SUI.Handlers.BackgroundBorder then
		SUI.Handlers.BackgroundBorder:SetVisible(bgInstanceID, false)
	end

	-- Clear element references
	preview.Health = nil
	preview.HealthPrediction = nil
	preview.Power = nil
	preview.Castbar = nil
	preview.Name = nil
	preview.FrameBackground = nil
	preview.elementList = {}
	preview.__tags = {}
end

---Build visual elements on a preview frame using real UF.Elements:Build()
---@param preview table
---@param frameName string
local function BuildPreviewElements(preview, frameName)
	local elementDB = preview.elementDB

	-- Phase 1: Build all elements (creates StatusBars, FontStrings, etc.)
	for _, elementName in ipairs(PREVIEW_ELEMENTS) do
		if elementDB[elementName] and elementDB[elementName].enabled then
			UF.Elements:Build(preview, elementName, elementDB[elementName])

			-- Store DB reference on element (matches what SpawnFrames does)
			if preview[elementName] then
				preview[elementName].DB = elementDB[elementName]
			end
		end
	end

	-- Phase 2: Call element Update functions (applies textures, colors, text visibility)
	-- This runs BEFORE positioning because Update functions set their own default
	-- positions that our positioning phase needs to override.
	for _, elementName in ipairs(PREVIEW_ELEMENTS) do
		if preview[elementName] and elementDB[elementName] and elementDB[elementName].enabled then
			UF.Elements:Update(preview, elementName, elementDB[elementName])
		end
	end

	-- Phase 3: Apply element positioning (overrides Update's default positioning)
	-- This matches SpawnFrames.lua where ElementUpdate runs AFTER Elements:Update
	for _, elementName in ipairs(PREVIEW_ELEMENTS) do
		if preview[elementName] and elementDB[elementName] then
			ApplyElementPosition(preview, elementName, elementDB[elementName])
		end
	end

	-- Phase 4: Apply mock data (health/power values, castbar progress, colors)
	ApplyMockData(preview)
end

---Create a new preview frame with mock-oUF shim
---@param frameName string
---@param index number
---@return table preview
local function CreatePreviewFrame(frameName, index)
	local f = CreateFrame('Button', 'SUI_Preview_' .. frameName .. '_' .. index, UIParent)

	-- oUF method stubs: Tag intercepts tag strings and applies mock text
	f.Tag = function(self, fs, ts, ...)
		if fs and ts then
			self.__tags = self.__tags or {}
			self.__tags[fs] = ts
			ApplyMockTag(fs, ts, self.mockData)
		end
	end
	f.Untag = function(self, fs)
		if self.__tags then
			self.__tags[fs] = nil
		end
	end
	f.UpdateTags = function(self)
		for fs, ts in pairs(self.__tags or {}) do
			ApplyMockTag(fs, ts, self.mockData)
		end
	end

	-- No-op stubs for oUF methods that elements may call
	f.RegisterEvent = function() end
	f.UnregisterEvent = function() end
	f.EnableElement = function() end
	f.DisableElement = function() end
	f.IsElementEnabled = function()
		return false
	end
	f.UpdateAllElements = function() end
	f.Enable = function() end
	f.Disable = function() end
	f.IsEnabled = function()
		return true
	end

	-- Required oUF properties
	f.__elements = {}
	f.__tags = {}
	f.unit = 'player'
	-- Use prefixed unitOnCreate to prevent Elements:Build from overwriting
	-- the real holder's elementList via _G['SUI_UF_' .. unitOnCreate .. '_Holder']
	f.unitOnCreate = '_preview_' .. frameName
	f._realFrameName = frameName
	f.elementList = {}

	-- Reuse oUF's color table for class/power colors
	if SUIUF and SUIUF.colors then
		f.colors = SUIUF.colors
	end

	-- Raised frame (Name element and overlays parent to this)
	f.raised = CreateFrame('Frame', nil, f)
	f.raised:SetFrameLevel(f:GetFrameLevel() + 100)
	f.raised.__owner = f

	-- Settings from CurrentSettings
	f.DB = UF.CurrentSettings[frameName]
	f.elementDB = f.DB.elements
	f.config = UF.Unit:GetConfig(frameName)

	-- Mock data
	f.mockData = UF.TestMode.GetMockData(index)
	f.isPreview = true

	-- BackgroundBorder instance tracking
	f._bgInstanceID = 'Preview_' .. frameName .. '_' .. index

	-- Size from settings
	f:SetSize(f.DB.width, UF:CalculateHeight(frameName))
	f:SetScale(f.DB.scale or 1)

	-- Click-through and visibility
	f:EnableMouse(false)
	f:SetFrameStrata('HIGH')

	return f
end

----------------------------------------------------------------------------------------------------
-- Preview Frame Positioning
----------------------------------------------------------------------------------------------------

---Position a single preview frame over the real frame
---@param frameName string
---@param preview table
local function PositionSinglePreview(frameName, preview)
	local realFrame = UF.Unit:Get(frameName)
	if not realFrame then
		return
	end

	preview:ClearAllPoints()
	preview:SetPoint('CENTER', realFrame, 'CENTER', 0, 0)
end

---Position group preview frames (boss, arena, party, raid)
---@param frameName string
---@param previewFrames table[]
local function PositionGroupPreviews(frameName, previewFrames)
	local holder = UF.Unit:Get(frameName)
	if not holder then
		return
	end

	local settings = UF.CurrentSettings[frameName]
	local frameHeight = UF:CalculateHeight(frameName)
	local yOffset = settings.yOffset or -1

	-- Boss/arena: simple vertical stack
	local config = UF.Unit:GetConfig(frameName)
	if config and config.config and config.config.useUnitWatch then
		for i, preview in ipairs(previewFrames) do
			preview:ClearAllPoints()
			if i == 1 then
				preview:SetPoint('TOPLEFT', holder, 'TOPLEFT', 0, 0)
			else
				preview:SetPoint('TOP', previewFrames[i - 1], 'BOTTOM', 0, yOffset)
			end
		end
		return
	end

	-- Party/raid: grid layout
	local unitsPerColumn = settings.unitsPerColumn or 5
	local maxColumns = settings.maxColumns or 1
	local columnSpacing = settings.columnSpacing or 0
	local columnAnchorPoint = settings.columnAnchorPoint or 'LEFT'
	local point = settings.point or 'TOP'
	local xOffset = settings.xOffset or 0

	for i, preview in ipairs(previewFrames) do
		preview:ClearAllPoints()

		local colIndex = math.floor((i - 1) / unitsPerColumn)
		local rowIndex = (i - 1) - (colIndex * unitsPerColumn)

		if rowIndex == 0 and colIndex == 0 then
			preview:SetPoint(point, holder, point, 0, 0)
		elseif rowIndex == 0 then
			-- First frame in a new column
			local prevColFirst = previewFrames[(colIndex - 1) * unitsPerColumn + 1]
			if point == 'TOP' or point == 'BOTTOM' then
				if columnAnchorPoint == 'LEFT' or columnAnchorPoint == 'TOPLEFT' or columnAnchorPoint == 'BOTTOMLEFT' then
					preview:SetPoint('LEFT', prevColFirst, 'RIGHT', columnSpacing, 0)
				else
					preview:SetPoint('RIGHT', prevColFirst, 'LEFT', -columnSpacing, 0)
				end
			else
				if columnAnchorPoint == 'TOP' or columnAnchorPoint == 'TOPLEFT' or columnAnchorPoint == 'TOPRIGHT' then
					preview:SetPoint('TOP', prevColFirst, 'BOTTOM', 0, -columnSpacing)
				else
					preview:SetPoint('BOTTOM', prevColFirst, 'TOP', 0, columnSpacing)
				end
			end
		else
			-- Stack within column
			local prev = previewFrames[i - 1]
			if point == 'TOP' then
				preview:SetPoint('TOP', prev, 'BOTTOM', 0, yOffset)
			elseif point == 'BOTTOM' then
				preview:SetPoint('BOTTOM', prev, 'TOP', 0, -yOffset)
			elseif point == 'LEFT' then
				preview:SetPoint('LEFT', prev, 'RIGHT', xOffset, 0)
			elseif point == 'RIGHT' then
				preview:SetPoint('RIGHT', prev, 'LEFT', -xOffset, 0)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Preview Frame Count Per Type
----------------------------------------------------------------------------------------------------

local PREVIEW_COUNTS = {
	boss = 4,
	arena = 3,
	party = 4,
	raid10 = 10,
	raid25 = 10,
	raid40 = 15,
}

---Get the number of preview frames to create for a frame type
---@param frameName string
---@return number
local function GetPreviewCount(frameName)
	local config = UF.Unit:GetConfig(frameName)
	if not config or not config.config or not config.config.IsGroup then
		return 1
	end
	return PREVIEW_COUNTS[frameName] or 1
end

----------------------------------------------------------------------------------------------------
-- Auto-refresh hooks: rebuild previews when settings change
----------------------------------------------------------------------------------------------------

-- Track which real frames we've hooked so we don't double-hook
local hookedFrames = {}

---Install hooks on a real frame's UpdateAll and ElementUpdate methods
---@param frameName string
local function HookRealFrame(frameName)
	if hookedFrames[frameName] then
		return
	end

	-- UF.Unit[frameName] is what Options.lua calls methods on
	-- (groupElement for groups, oUF frame for singles)
	local realFrame = UF.Unit[frameName]
	if not realFrame then
		return
	end

	if realFrame.UpdateAll then
		hooksecurefunc(realFrame, 'UpdateAll', function()
			if PreviewFrame:IsShowing(frameName) then
				PreviewFrame:Refresh(frameName)
			end
		end)
	end

	if realFrame.ElementUpdate then
		hooksecurefunc(realFrame, 'ElementUpdate', function()
			if PreviewFrame:IsShowing(frameName) then
				PreviewFrame:Refresh(frameName)
			end
		end)
	end

	hookedFrames[frameName] = true
end

----------------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------------

---Show preview frames for a specific unit frame
---@param frameName string
function PreviewFrame:Show(frameName)
	local settings = UF.CurrentSettings[frameName]
	if not settings or not settings.enabled then
		return
	end

	-- Ensure we have a real frame to anchor to
	local realFrame = UF.Unit:Get(frameName)
	if not realFrame then
		return
	end

	-- Hook real frame's update methods so preview auto-refreshes on changes
	HookRealFrame(frameName)

	local data = previews[frameName]
	if not data then
		data = { frames = {}, showing = false }
		previews[frameName] = data
	end

	local count = GetPreviewCount(frameName)

	-- Create preview frames as needed
	for i = 1, count do
		if not data.frames[i] then
			data.frames[i] = CreatePreviewFrame(frameName, i)
		else
			-- Refresh settings on existing frame
			local preview = data.frames[i]
			preview.DB = UF.CurrentSettings[frameName]
			preview.elementDB = preview.DB.elements
			preview:SetSize(preview.DB.width, UF:CalculateHeight(frameName))
			preview:SetScale(preview.DB.scale or 1)
		end
	end

	-- Build elements and show
	for i = 1, count do
		local preview = data.frames[i]
		CleanPreviewFrame(preview)
		BuildPreviewElements(preview, frameName)
		preview:Show()
	end

	-- Position
	local config = UF.Unit:GetConfig(frameName)
	if config and config.config and config.config.IsGroup then
		PositionGroupPreviews(frameName, data.frames)
	else
		PositionSinglePreview(frameName, data.frames[1])
	end

	data.showing = true
end

---Hide preview frames for a specific unit frame
---@param frameName string
function PreviewFrame:Hide(frameName)
	local data = previews[frameName]
	if not data then
		return
	end

	for _, preview in ipairs(data.frames) do
		preview:Hide()
	end

	data.showing = false
end

---Show previews for all enabled unit frames
function PreviewFrame:ShowAll()
	local mockIdx = 0
	for frameName in pairs(UF.Unit:GetBuiltFrameList()) do
		local settings = UF.CurrentSettings[frameName]
		if settings and settings.enabled then
			-- Update mock data indices for variety
			local count = GetPreviewCount(frameName)
			local data = previews[frameName]
			if not data then
				data = { frames = {}, showing = false }
				previews[frameName] = data
			end
			for i = 1, count do
				mockIdx = mockIdx + 1
				if data.frames[i] then
					data.frames[i].mockData = UF.TestMode.GetMockData(mockIdx)
				end
			end
			self:Show(frameName)
		end
	end
end

---Hide all preview frames
function PreviewFrame:HideAll()
	for frameName in pairs(previews) do
		self:Hide(frameName)
	end
end

---Check if previews are showing for a specific frame
---@param frameName string
---@return boolean
function PreviewFrame:IsShowing(frameName)
	local data = previews[frameName]
	return data ~= nil and data.showing
end

---Check if any preview is active
---@return boolean
function PreviewFrame:IsActive()
	for _, data in pairs(previews) do
		if data.showing then
			return true
		end
	end
	return false
end

---Refresh previews for a specific frame (destroy + rebuild)
---@param frameName string
function PreviewFrame:Refresh(frameName)
	local data = previews[frameName]
	if not data or not data.showing then
		return
	end

	for _, preview in ipairs(data.frames) do
		CleanPreviewFrame(preview)
		preview.DB = UF.CurrentSettings[frameName]
		preview.elementDB = preview.DB.elements
		preview:SetSize(preview.DB.width, UF:CalculateHeight(frameName))
		preview:SetScale(preview.DB.scale or 1)
		BuildPreviewElements(preview, frameName)
	end

	-- Re-position in case size changed
	local config = UF.Unit:GetConfig(frameName)
	if config and config.config and config.config.IsGroup then
		PositionGroupPreviews(frameName, data.frames)
	end
end

---Refresh all active previews
function PreviewFrame:RefreshAll()
	for frameName, data in pairs(previews) do
		if data.showing then
			self:Refresh(frameName)
		end
	end
end

-- Hook the global UF:UpdateAll for batch updates (profile changes, etc.)
hooksecurefunc(UF, 'UpdateAll', function()
	if PreviewFrame:IsActive() then
		PreviewFrame:RefreshAll()
	end
end)
