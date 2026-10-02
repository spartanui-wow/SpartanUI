local _, ns = ...
---@class SUI.UF
local UF = SUI.UF

local PreviewFrame = {}
UF.PreviewFrame = PreviewFrame

-- Storage for active preview frames
local previews = {} -- previews[frameName] = { frames = {}, showing = false }

-- Elements to build on preview frames (visual-only elements)
-- Order matches the real builder order (player.lua) so relative positioning works
local PREVIEW_ELEMENTS = {
	'SpartanArt',
	'FrameBackground',
	'Name',
	'Health',
	'Castbar',
	'Power',
	'Portrait',
	'ClassIcon',
	'RaidTargetIndicator',
	'LeaderIndicator',
	'RaidRoleIndicator',
	'RestingIndicator',
	'CombatIndicator',
	'ReadyCheckIndicator',
}

-- Indicators are normally shown by game state (in combat, resting, raid mark). The preview
-- shows each enabled one with a sample icon so its size and place can be seen.
local SAMPLE_INDICATORS = {
	RaidTargetIndicator = function(element)
		element:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons')
		SetRaidTargetIconTexture(element, 8)
	end,
	LeaderIndicator = function(element)
		element:SetTexture('Interface\\GroupFrame\\UI-Group-LeaderIcon')
		element:SetTexCoord(0, 1, 0, 1)
	end,
	RaidRoleIndicator = function(element)
		element:SetTexture('Interface\\GroupFrame\\UI-Group-MainTankIcon')
		element:SetTexCoord(0, 1, 0, 1)
	end,
	RestingIndicator = function(element)
		element:SetTexture('Interface\\CharacterFrame\\UI-StateIcon')
		element:SetTexCoord(0, 0.5, 0, 0.421875)
	end,
	CombatIndicator = function(element)
		element:SetTexture('Interface\\CharacterFrame\\UI-StateIcon')
		element:SetTexCoord(0.5, 1, 0, 0.484375)
	end,
	ReadyCheckIndicator = function(element)
		element:SetTexture('Interface\\RaidFrame\\ReadyCheck-Ready')
		element:SetTexCoord(0, 1, 0, 1)
	end,
	ClassIcon = function(element, mock)
		local coords = CLASS_ICON_TCOORDS and mock and CLASS_ICON_TCOORDS[mock.class]
		if coords then
			element:SetTexture('Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES')
			element:SetTexCoord(unpack(coords))
		end
		if element.shadow then
			element.shadow:Show()
		end
	end,
}

---Show sample indicators and point the portrait at the player
---@param preview table
local function ApplySampleVisuals(preview)
	local elementDB = preview.elementDB
	for name, apply in pairs(SAMPLE_INDICATORS) do
		local element = preview[name]
		if element and elementDB[name] and elementDB[name].enabled then
			apply(element, preview.mockData)
			element:Show()
		end
	end

	-- The portrait's click button is a secure unit button for the real frame; keep it hidden here
	if preview.PortraitClickOverlay then
		preview.PortraitClickOverlay:Hide()
	end
	local portraitDB = elementDB.Portrait
	if preview.Portrait and portraitDB and portraitDB.enabled then
		if portraitDB.type == '3D' and preview.Portrait3D then
			preview.Portrait3D:ClearModel()
			preview.Portrait3D:SetUnit('player')
		elseif preview.Portrait2D then
			SetPortraitTexture(preview.Portrait2D, 'player')
		end
	end
end

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

----------------------------------------------------------------------------------------------------
-- Sample aura icons
----------------------------------------------------------------------------------------------------

-- Blizzard's aura containers cannot run on a preview frame, so draw sample icons laid out
-- from the same settings the real container uses
local SAMPLE_AURA_ELEMENTS = { 'BuffContainer', 'DebuffContainer', 'CustomAuras' }
local SAMPLE_ICONS = {
	BuffContainer = {
		'Interface\\Icons\\Spell_Holy_Renew',
		'Interface\\Icons\\Spell_Holy_PowerWordShield',
		'Interface\\Icons\\Spell_Nature_Rejuvenation',
		'Interface\\Icons\\Spell_Holy_WordFortitude',
		'Interface\\Icons\\Spell_Holy_MagicalSentry',
		'Interface\\Icons\\Spell_Nature_Regeneration',
	},
	DebuffContainer = {
		'Interface\\Icons\\Spell_Shadow_ShadowWordPain',
		'Interface\\Icons\\Spell_Shadow_CurseOfTounges',
		'Interface\\Icons\\Spell_Nature_CorrosiveBreath',
		'Interface\\Icons\\Spell_Frost_FrostNova',
	},
	CustomAuras = {
		'Interface\\Icons\\Spell_Nature_Lightning',
		'Interface\\Icons\\Spell_Holy_SealOfMight',
	},
}
local MAX_SAMPLE_ROWS = 2

---@param preview table
---@param elementName string
---@param DB table|nil
local function DrawSampleAuras(preview, elementName, DB)
	local key = '_sample' .. elementName
	local holder = preview[key]
	if not DB or not DB.enabled then
		if holder then
			holder:Hide()
		end
		return
	end
	if not holder then
		holder = CreateFrame('Frame', nil, preview)
		holder.icons = {}
		holder.sampleName = elementName
		preview[key] = holder
	end

	local size = DB.size or 24
	local spacing = DB.spacing or 2
	local perRow = math.max(1, DB.perRow or 8)
	local count = math.min(DB.number or perRow, perRow * MAX_SAMPLE_ROWS)
	local anchor = (DB.position and DB.position.anchor) or 'TOPLEFT'
	local xDir = (DB.growthx or 'RIGHT') == 'LEFT' and -1 or 1
	local yDir = (DB.growthy or 'UP') == 'DOWN' and -1 or 1
	local textures = SAMPLE_ICONS[elementName] or SAMPLE_ICONS.BuffContainer

	for i = 1, count do
		local icon = holder.icons[i]
		if not icon then
			icon = holder:CreateTexture(nil, 'ARTWORK')
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			holder.icons[i] = icon
		end
		local col = (i - 1) % perRow
		local row = math.floor((i - 1) / perRow)
		icon:SetTexture(textures[((i - 1) % #textures) + 1])
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		icon:SetPoint(anchor, holder, anchor, xDir * col * (size + spacing), yDir * row * (size + spacing))
		icon:Show()
	end
	for i = count + 1, #holder.icons do
		holder.icons[i]:Hide()
	end

	local rows = math.ceil(count / perRow)
	local cols = math.min(count, perRow)
	holder:SetSize(math.max(1, cols * (size + spacing) - spacing), math.max(1, rows * (size + spacing) - spacing))

	local position = DB.position or {}
	local relativeTo = preview
	if position.relativeTo and position.relativeTo ~= 'Frame' and preview[position.relativeTo] then
		relativeTo = preview[position.relativeTo]
	end
	holder:ClearAllPoints()
	holder:SetPoint(anchor, relativeTo, position.relativePoint or anchor, position.x or 0, position.y or 0)
	holder:SetFrameLevel(preview.raised:GetFrameLevel() + 1)
	holder:Show()
end

---Build each enabled element once, then update it in place. Frames are never freed in WoW,
---so rebuilding on every settings change (every slider tick) would leak.
---@param preview table
---@param frameName string
local function BuildPreviewElements(preview, frameName)
	local elementDB = preview.elementDB
	preview.built = preview.built or {}
	-- Elements set absolute frame levels meant for a frame near level 0; build and update at
	-- those levels, then lift the whole tree (see PreviewFrame:LiftLevels)
	PreviewFrame:RestoreLevels(preview)
	if preview.levelBase and not preview.naturalLevels then
		-- Reparenting into the options window raised these; start from where a real frame sits
		preview:SetFrameLevel(1)
		preview.raised:SetFrameLevel(101)
		preview.naturalLevels = true
	end

	local realFrame = UF.Unit:Get(frameName)
	local allowed = realFrame and realFrame.elementList
	for _, elementName in ipairs(PREVIEW_ELEMENTS) do
		local db = elementDB[elementName]
		local wanted = db and db.enabled and (not allowed or allowed[elementName])
		if elementName == 'Portrait' and not preview.built.Portrait and InCombatLockdown() then
			wanted = false
		end
		if wanted then
			if not preview.built[elementName] then
				UF.Elements:Build(preview, elementName, db)
				preview.built[elementName] = true
				-- oUF never enables elements on the stand-in, so give the art its drawing hook here
				if elementName == 'SpartanArt' and preview.SpartanArt and ns.SpartanArtForceUpdate then
					preview.SpartanArt.__owner = preview
					preview.SpartanArt.ForceUpdate = ns.SpartanArtForceUpdate
				end
			end
			if preview[elementName] then
				preview[elementName].DB = db
				preview[elementName]:Show()
			end
		elseif preview.built[elementName] and preview[elementName] then
			preview[elementName]:Hide()
		end
	end

	-- Update runs before positioning because Update sets its own default positions that the
	-- position data overrides, matching SpawnFrames.lua
	for _, elementName in ipairs(PREVIEW_ELEMENTS) do
		if preview[elementName] and elementDB[elementName] and elementDB[elementName].enabled then
			UF.Elements:Update(preview, elementName, elementDB[elementName])
		end
	end

	for _, elementName in ipairs(PREVIEW_ELEMENTS) do
		if preview[elementName] and elementDB[elementName] and elementDB[elementName].enabled then
			ApplyElementPosition(preview, elementName, elementDB[elementName])
		end
	end

	ApplyMockData(preview)
	ApplySampleVisuals(preview)

	for _, elementName in ipairs(SAMPLE_AURA_ELEMENTS) do
		DrawSampleAuras(preview, elementName, elementDB[elementName])
	end

	if preview.fixedStrata then
		PreviewFrame:ApplyStrata(preview, preview.fixedStrata)
	end
	if preview.levelBase then
		PreviewFrame:LiftLevels(preview, preview.levelBase)
	end
end

---Frames in the preview, parents before children
---@param preview Frame
---@return Frame[]
local function CollectFrames(preview)
	local list = {}
	local function Walk(frame)
		list[#list + 1] = frame
		for _, child in ipairs({ frame:GetChildren() }) do
			Walk(child)
		end
	end
	Walk(preview)
	return list
end

---Raise every frame in the preview so its lowest level sits at `base`, keeping each part's
---level relative to the others exactly as the elements set them. Levels are set one by one,
---parent first, so the result does not depend on how the client moves children.
---@param preview Frame
---@param base number
function PreviewFrame:LiftLevels(preview, base)
	local frames = CollectFrames(preview)
	local natural = {}
	local lowest
	for i, frame in ipairs(frames) do
		natural[i] = frame:GetFrameLevel()
		lowest = lowest and math.min(lowest, natural[i]) or natural[i]
	end
	local shift = math.max(0, base - (lowest or 0))
	preview.levelShift = {}
	for i, frame in ipairs(frames) do
		frame:SetFrameLevel(math.min(9000, natural[i] + shift))
		preview.levelShift[frame] = natural[i]
	end
end

---Put every lifted frame back on the level the elements gave it
---@param preview Frame
function PreviewFrame:RestoreLevels(preview)
	if not preview.levelShift then
		return
	end
	for _, frame in ipairs(CollectFrames(preview)) do
		local natural = preview.levelShift[frame]
		if natural then
			frame:SetFrameLevel(natural)
		end
	end
	preview.levelShift = nil
end

---Elements pick their own strata (often BACKGROUND). Inside the options window that would
---draw them behind the window, so move the whole preview tree to one strata.
---@param preview Frame
---@param strata string
function PreviewFrame:ApplyStrata(preview, strata)
	local function Walk(frame)
		frame:SetFrameStrata(strata)
		for _, child in ipairs({ frame:GetChildren() }) do
			Walk(child)
		end
	end
	Walk(preview)
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

---Position group preview frames (boss, arena, party, raid) the way the real group grows
---@param frameName string
---@param previewFrames table[]
local function PositionGroupPreviews(frameName, previewFrames)
	local holder = UF.Unit:Get(frameName)
	if not holder then
		return
	end

	local offsets, _, _, left, top = UF.Unit:GroupOffsets(frameName, #previewFrames)
	local halfWidth = (UF.CurrentSettings[frameName].width or 180) / 2
	local halfHeight = (UF:CalculateHeight(frameName) or 40) / 2
	for i, preview in ipairs(previewFrames) do
		preview:ClearAllPoints()
		preview:SetPoint('TOPLEFT', holder, 'TOPLEFT', offsets[i][1] - halfWidth - left, offsets[i][2] + halfHeight - top)
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

----------------------------------------------------------------------------------------------------
-- Options window preview (the Stage)
----------------------------------------------------------------------------------------------------

local stageFrames = {} -- stageFrames[frameName] = { frame, ... }
local STAGE_COUNTS = { party = 5, boss = 5, arena = 3, raid = 10 }

---How many sample frames the options preview shows for a frame type
---@param frameName string
---@return number
function PreviewFrame:GetStageCount(frameName)
	local config = UF.Unit:GetConfig(frameName)
	if not config or not config.config or not config.config.IsGroup then
		return 1
	end
	-- Enough frames to show how the group grows, never more than it can show
	local count = STAGE_COUNTS[frameName] or 3
	if config.unitsPerColumn then
		count = math.min(count, config.unitsPerColumn * math.max(1, config.maxColumns or 1))
	end
	return math.max(1, count)
end

---Draw sample frames for a unit frame inside `parent`, reusing frames between calls
---@param frameName string
---@param parent Frame
---@return table[] frames The drawn frames, left to right
function PreviewFrame:RenderStage(frameName, parent)
	for otherName, otherList in pairs(stageFrames) do
		if otherName ~= frameName then
			for _, other in ipairs(otherList) do
				other:Hide()
			end
		end
	end
	local list = stageFrames[frameName]
	if not list then
		list = {}
		stageFrames[frameName] = list
	end
	local count = self:GetStageCount(frameName)
	for i = 1, count do
		local preview = list[i]
		if not preview then
			preview = CreatePreviewFrame(frameName, 100 + i)
			preview.mockData = UF.TestMode.GetMockData(i)
			list[i] = preview
		end
		preview:SetParent(parent)
		preview.fixedStrata = parent:GetFrameStrata()
		preview.levelBase = parent:GetFrameLevel() + 5
		preview.DB = UF.CurrentSettings[frameName]
		preview.elementDB = preview.DB.elements
		preview:SetSize(preview.DB.width, UF:CalculateHeight(frameName))
		BuildPreviewElements(preview, frameName)
		preview:Show()
	end
	for i = count + 1, #list do
		list[i]:Hide()
	end
	local drawn = {}
	for i = 1, count do
		drawn[i] = list[i]
	end
	return drawn
end

---Hide every options preview frame
function PreviewFrame:HideStage()
	for _, list in pairs(stageFrames) do
		for _, preview in ipairs(list) do
			preview:Hide()
		end
	end
end

-- Hook the global UF:UpdateAll for batch updates (profile changes, etc.)
hooksecurefunc(UF, 'UpdateAll', function()
	if PreviewFrame:IsActive() then
		PreviewFrame:RefreshAll()
	end
end)
