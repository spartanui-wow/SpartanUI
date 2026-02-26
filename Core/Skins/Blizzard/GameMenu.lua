---@class SUI.Module.Handler.GameMenu : SUI.Module
local SUIGameMenu = SUI:NewModule('Handler.GameMenu', 'AceEvent-3.0')
local GameMenuFrame = GameMenuFrame
---@class SUIMenuSkin : Frame
local MenuSkin = _G['SUIMenuSkin'] or CreateFrame('Frame', 'SUIMenuSkin', UIParent)
local ActiveSkin = SUI.IsRetail and 'Midnight' or 'Base' -- Base, Midnight

-- Logger integration - create a hierarchical logger under SpartanUI.Skins.GameMenu
local logger = {
	debug = function(msg)
		if SUI.Log then
			SUI.Log(msg, 'Skins.GameMenu', 'debug')
		end
	end,
	info = function(msg)
		if SUI.Log then
			SUI.Log(msg, 'Skins.GameMenu', 'info')
		end
	end,
	warning = function(msg)
		if SUI.Log then
			SUI.Log(msg, 'Skins.GameMenu', 'warning')
		end
	end,
	error = function(msg)
		if SUI.Log then
			SUI.Log(msg, 'Skins.GameMenu', 'error')
		end
	end,
}

---@param frame Frame The frame to reskin buttons for (typically GameMenuFrame)
local function ReskinGameMenuButtons(frame)
	-- Check if the frame exists
	if not frame then
		return
	end

	-- Loop through all the child frames
	for _, child in pairs({ frame:GetChildren() }) do
		-- Check if the child is a button
		if child:IsObjectType('Button') then
			-- Reskin the button
			child:SetNormalAtlas('auctionhouse-nav-button')
			child:SetHighlightAtlas('auctionhouse-nav-button-highlight')
			child:SetPushedAtlas('auctionhouse-nav-button-select')

			-- Apply texture coordinates to all texture layers
			local normalTexture = child:GetNormalTexture()
			local highlightTexture = child:GetHighlightTexture()
			local pushedTexture = child:GetPushedTexture()

			if normalTexture then
				normalTexture:SetTexCoord(0, 1, 0, 0.7)
			end

			-- Fix for non-retail: Apply SetTexCoord to highlight and pushed textures as well
			if highlightTexture then
				highlightTexture:SetTexCoord(0, 1, 0, 1)
			end

			if pushedTexture then
				pushedTexture:SetTexCoord(0, 1, 0, 1)
			end

			-- Adjust text position if needed
			local text = child:GetFontString()
			if text then
				text:ClearAllPoints()
				text:SetPoint('CENTER', child, 'CENTER', 0, 0)
			end

			-- Remove old textures
			for _, region in pairs({ child:GetRegions() }) do
				if region:IsObjectType('Texture') and region ~= normalTexture and region ~= highlightTexture and region ~= pushedTexture then
					region:Hide()
				end
			end

			-- Adjust button size if needed
			local width, height = 200, 36
			if not SUI.IsRetail then
				width, height = 150, 30
			end
			child:SetSize(width, height)
		end
	end
end

function SUIGameMenu:IsDisabled()
	if SUI:IsAddonEnabled('Skinner') or SUI:IsAddonEnabled('ConsolePort') or not SUI.Skins.DB.components['Blizzard'].enabled then
		return true
	end
	return false
end

function SUIGameMenu:OnEnable()
	if SUIGameMenu:IsDisabled() then
		return
	end
	-- Set up hooks
	GameMenuFrame:HookScript('OnShow', function()
		if SUIGameMenu:IsDisabled() then
			return
		end
		ReskinGameMenuButtons(GameMenuFrame)

		MenuSkin:OnFrameShown(true)
	end)
	GameMenuFrame:HookScript('OnHide', function()
		if SUIGameMenu:IsDisabled() then
			return
		end
		MenuSkin:OnFrameShown(false)
		MenuSkin:ResetAnimation()
	end)

	-- Use direct texture file from Interface\AddOns\SpartanUI\images\Menu\UIGearUpdate.png
	-- This ensures consistency across all WoW versions (Retail, TBC, Mists, Classic)
	local texturePath = 'Interface\\AddOns\\SpartanUI\\images\\Menu\\' .. ActiveSkin .. '.png'

	-- Background: gearUpdate-BG coordinates
	MenuSkin.Background:SetTexture(texturePath)
	MenuSkin.Background:SetTexCoord(0.0009765625, 0.7060546875, 0.00048828125, 0.58251953125)

	-- Top Line: gearUpdate-glow-filigree coordinates (flipped vertically)
	MenuSkin.TopLine:SetTexture(texturePath)
	MenuSkin.TopLine:SetTexCoord(0.0009765625, 0.6865234375, 0.70947265625, 0.58349609375)
	MenuSkin.TopLine:SetAlpha(0.5)

	-- Bottom Line: gearUpdate-glow-filigree coordinates
	MenuSkin.BottomLine:SetTexture(texturePath)
	MenuSkin.BottomLine:SetTexCoord(0.0009765625, 0.6865234375, 0.58349609375, 0.70947265625)
	MenuSkin.BottomLine:SetAlpha(0.5)

	if GameMenuFrame.Layout then
		hooksecurefunc(GameMenuFrame, 'Layout', function()
			if SUIGameMenu:IsDisabled() then
				return
			end
			MenuSkin:OnFrameShown(GameMenuFrame:IsShown())
		end)
	end
end

local function CreateMenuSkin()
	-- Size matches gearUpdate-BG dimensions: 361x596
	MenuSkin:SetSize(SUI.IsRetail and 361 or 300, SUI.IsRetail and 596 or 500)
	MenuSkin:SetFrameStrata('BACKGROUND')
	MenuSkin:SetScale(0.8)
	MenuSkin:Hide()

	-- Gradient
	MenuSkin.Gradient = MenuSkin:CreateTexture(nil, 'BACKGROUND', nil, 2)
	MenuSkin.Gradient:SetAllPoints()
	MenuSkin.Gradient:SetTexture('Interface\\AddOns\\SpartanUI\\images\\Menu\\Gradient.jpg')
	MenuSkin.Gradient:SetAlpha(0.4)

	-- Background
	MenuSkin.Background = MenuSkin:CreateTexture(nil, 'BACKGROUND')
	MenuSkin.Background:SetPoint('CENTER')

	-- Mask
	MenuSkin.Mask = MenuSkin:CreateMaskTexture()
	MenuSkin.Mask:SetTexture('Interface\\AddOns\\SpartanUI\\images\\Menu\\RingMask.png')
	MenuSkin.Mask:SetAllPoints(MenuSkin.Gradient)
	MenuSkin.Background:AddMaskTexture(MenuSkin.Mask)
	MenuSkin.Gradient:AddMaskTexture(MenuSkin.Mask)

	-- Top Line
	MenuSkin.TopLine = MenuSkin:CreateTexture(nil, 'ARTWORK')
	if ActiveSkin == 'Midnight' then
		MenuSkin.TopLine:SetSize(600, 230)
		MenuSkin.TopLine:SetScale(0.6)
	else
		MenuSkin.TopLine:SetSize(600, 100)
	end

	MenuSkin.TopLine:SetPoint('TOP', 0, 100)

	-- Logo Button
	MenuSkin.LogoButton = CreateFrame('Button', nil, MenuSkin)
	MenuSkin.LogoButton:SetSize(80, 80)
	-- if SUI.IsTBC then
	-- 	MenuSkin.LogoButton:SetPoint('BOTTOM', 0, -10)
	-- else
	MenuSkin.LogoButton:SetPoint('BOTTOM', 0, -25)
	-- end

	MenuSkin.LogoButton.texture = MenuSkin.LogoButton:CreateTexture(nil, 'ARTWORK')
	MenuSkin.LogoButton.texture:SetTexture('Interface\\AddOns\\SpartanUI\\images\\Menu\\SUILogo_white.png')
	MenuSkin.LogoButton.texture:SetAllPoints()
	MenuSkin.LogoButton.texture:AddMaskTexture(MenuSkin.Mask)

	-- Mousedown state texture
	MenuSkin.LogoButton.mousedownTexture = MenuSkin.LogoButton:CreateTexture(nil, 'ARTWORK')
	MenuSkin.LogoButton.mousedownTexture:SetTexture('Interface\\AddOns\\SpartanUI\\images\\Menu\\SUILogo_black.png')
	MenuSkin.LogoButton.mousedownTexture:SetAllPoints()
	MenuSkin.LogoButton.mousedownTexture:AddMaskTexture(MenuSkin.Mask)
	MenuSkin.LogoButton.mousedownTexture:Hide()

	-- Highlight effect
	MenuSkin.LogoButton.highlight = MenuSkin.LogoButton:CreateTexture(nil, 'HIGHLIGHT')
	MenuSkin.LogoButton.highlight:SetTexture('Interface\\AddOns\\SpartanUI\\images\\Menu\\ItemBorderOuterHighlight.jpg')
	MenuSkin.LogoButton.highlight:SetSize(MenuSkin.LogoButton:GetWidth() * 2.4, MenuSkin.LogoButton:GetWidth() * 2.4)
	MenuSkin.LogoButton.highlight:SetPoint('CENTER')
	MenuSkin.LogoButton.highlight:SetBlendMode('ADD')
	MenuSkin.LogoButton.highlight:SetAlpha(0)

	MenuSkin.LogoButton:SetScript('OnEnter', function(self)
		self.highlight:SetAlpha(0.5)
	end)

	MenuSkin.LogoButton:SetScript('OnLeave', function(self)
		self.highlight:SetAlpha(0)
	end)

	MenuSkin.LogoButton:SetScript('OnMouseDown', function(self)
		self.texture:Hide()
		self.highlight:SetAlpha(0)
		self.mousedownTexture:Show()
	end)

	MenuSkin.LogoButton:SetScript('OnMouseUp', function(self)
		self.texture:Show()
		self.mousedownTexture:Hide()
	end)

	MenuSkin.LogoButton:SetScript('OnClick', function()
		SUI.Options:ToggleOptions()
		if not InCombatLockdown() then
			HideUIPanel(GameMenuFrame)
		end
	end)

	-- Bottom Line
	MenuSkin.BottomLine = MenuSkin:CreateTexture(nil, 'ARTWORK')
	if ActiveSkin == 'Midnight' then
		MenuSkin.BottomLine:SetSize(600, 230)
		MenuSkin.BottomLine:SetScale(0.6)
	else
		MenuSkin.BottomLine:SetSize(600, 100)
	end
	MenuSkin.BottomLine:SetPoint('BOTTOM', 0, -90)

	-- Line Mask
	MenuSkin.LineMask = MenuSkin:CreateMaskTexture()
	MenuSkin.LineMask:SetTexture('Interface\\AddOns\\SpartanUI\\images\\Menu\\SquareMask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
	MenuSkin.LineMask:SetPoint('TOPLEFT', MenuSkin.Gradient, 'TOPLEFT', 100, 0)
	MenuSkin.LineMask:SetPoint('BOTTOMRIGHT', MenuSkin.Gradient, 'BOTTOMRIGHT', -100, 0)
	MenuSkin.TopLine:AddMaskTexture(MenuSkin.LineMask)
	MenuSkin.BottomLine:AddMaskTexture(MenuSkin.LineMask)
	MenuSkin.Gradient:AddMaskTexture(MenuSkin.LineMask)
	MenuSkin.Background:AddMaskTexture(MenuSkin.LineMask)

	return MenuSkin
end

CreateMenuSkin()

MenuSkin:SetFrameStrata(GameMenuFrame:GetFrameStrata())
--Default Level is 1, alot of items will display at this level so lets bump it up
GameMenuFrame:SetFrameLevel(300)
MenuSkin:SetFrameLevel(299)
---------------------------------------------------------------
-- Settings
---------------------------------------------------------------

function MenuSkin:OnDataLoaded()
	self:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', self:GetTargetOffsets(GameMenuFrame))
end

MenuSkin:SetScript('OnEvent', function(event, ...)
	if MenuSkin[event] then
		MenuSkin[event](MenuSkin, ...)
	end
end)

function MenuSkin:ResetAnimation()
	self:ClearAllPoints()
	self:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	self.Gradient:ClearAllPoints()
	self.Gradient:SetPoint('TOPLEFT', 0, 0)
	self.Gradient:SetPoint('BOTTOMRIGHT', 0, 0)
	self.TopLine:ClearAllPoints()
	self.TopLine:SetPoint('TOP', 0, 100)
	self.BottomLine:ClearAllPoints()
	if ActiveSkin == 'Midnight' then
		self.BottomLine:SetPoint('BOTTOM', 0, -300)
	else
		self.BottomLine:SetPoint('BOTTOM', 0, -140)
	end
end

function MenuSkin:OnFrameShown(showMenu)
	if showMenu then
		if SUI.IsTBC then
			GameMenuFrame:SetScale(SUI.Skins.DB.Blizzard.GameMenu.Scale or 0.6)
		else
			GameMenuFrame:SetScale(SUI.Skins.DB.Blizzard.GameMenu.Scale or 0.8)
		end
		self:ResetAnimation()
		self:OnDataLoaded()
		self:InterpolatePoints(GameMenuFrame)
		self:SkinGameMenu()
		self:Show()
	else
		self:Hide()
		self:SetScript('OnUpdate', nil)
	end
end

function MenuSkin:GetTargetOffsets(target)
	local relScale = self:GetEffectiveScale() / target:GetEffectiveScale()
	local targetX, targetY = target:GetCenter()
	return targetX / relScale, targetY / relScale
end

function MenuSkin:SkinGameMenu()
	-- Hide Border and Header frames that exist in Classic/Mists/TBC versions
	-- These are defined in MainMenuFrameTemplate and need to be hidden for our custom skin

	if logger.debug then
		logger.debug('SkinGameMenu called - Border exists:', GameMenuFrame.Border ~= nil, 'Header exists:', GameMenuFrame.Header ~= nil)
	end

	SUI.Skins.RemoveAllTextures(GameMenuFrame)
	if GameMenuFrameHeader then
		SUI.Skins.RemoveTextures(GameMenuFrameHeader)
		GameMenuFrameHeader:Hide()
	end
	-- Hide NineSlice border parts that might be direct children of GameMenuFrame (Mists/Classic)
	local nineSliceParts = {
		'TopLeftCorner',
		'TopRightCorner',
		'BottomLeftCorner',
		'BottomRightCorner',
		'TopEdge',
		'BottomEdge',
		'LeftEdge',
		'RightEdge',
		'Center',
		'Header',
	}

	-- First check for direct children of GameMenuFrame
	for _, partName in ipairs(nineSliceParts) do
		if GameMenuFrame[partName] then
			GameMenuFrame[partName]:Hide()
		end
	end

	if GameMenuFrame.Border then
		GameMenuFrame.Border:Hide()
		GameMenuFrame.Border:SetAlpha(0)

		-- Clear the backdrop which contains the dialog border texture
		if GameMenuFrame.Border.SetBackdrop then
			GameMenuFrame.Border:SetBackdrop(nil)
			if logger.debug then
				logger.debug('Cleared Border backdrop')
			end
		end

		-- Hide NineSlice elements (used in Classic/Mists/TBC)
		if GameMenuFrame.Border.NineSlice then
			GameMenuFrame.Border.NineSlice:Hide()
			GameMenuFrame.Border.NineSlice:SetAlpha(0)
			if logger.debug then
				logger.debug('Hidden NineSlice border')
			end
		end

		-- Hide all named NineSlice textures under Border
		for _, partName in ipairs(nineSliceParts) do
			if GameMenuFrame.Border[partName] then
				GameMenuFrame.Border[partName]:Hide()
				GameMenuFrame.Border[partName]:SetAlpha(0)
				if logger.debug then
					logger.debug('Hidden Border.' .. partName)
				end
			end
		end

		-- Hide all border textures to ensure clean appearance
		local textureCount = 0
		for _, region in pairs({ GameMenuFrame.Border:GetRegions() }) do
			if region:IsObjectType('Texture') then
				region:Hide()
				region:SetAlpha(0)
				textureCount = textureCount + 1
			end
		end

		if logger.debug then
			logger.debug('Hidden', textureCount, 'border textures')
		end

		-- Hook to keep it hidden if the game tries to show it again
		GameMenuFrame.Border:SetScript('OnShow', function(self)
			if logger.debug then
				logger.debug('Border OnShow triggered - hiding it again')
			end
			self:Hide()
		end)
	end

	if GameMenuFrame.Header then
		if logger.debug then
			logger.debug('Hiding GameMenuFrame.Header')
		end

		GameMenuFrame.Header:Hide()
		GameMenuFrame.Header:SetAlpha(0)

		-- Hide header textures as well
		local headerTextureCount = 0
		for _, region in pairs({ GameMenuFrame.Header:GetRegions() }) do
			if region:IsObjectType('Texture') then
				region:Hide()
				region:SetAlpha(0)
				headerTextureCount = headerTextureCount + 1
			end
		end

		if logger.debug then
			logger.debug('Hidden', headerTextureCount, 'header textures')
		end

		-- Hook to keep it hidden
		GameMenuFrame.Header:SetScript('OnShow', function(self)
			if logger.debug then
				logger.debug('Header OnShow triggered - hiding it again')
			end
			self:Hide()
		end)
	end
end

---------------------------------------------------------------
-- Animation
---------------------------------------------------------------

-- Lerp compatibility function for older WoW versions
local Lerp = Lerp or function(startValue, endValue, amount)
	return startValue + (endValue - startValue) * amount
end

local x, y = 4, 5
function MenuSkin:InterpolatePoints(center)
	if SUIGameMenu:IsDisabled() then
		return
	end
	local heightOffset = SUI.IsRetail and 0 or -100
	if SUI.IsTBC then
		heightOffset = -50
	end

	local MainFramePosition = { self:GetPoint() }
	local gradientEndPoint = { self.Gradient:GetPoint(1) }
	local secondGradientPoint = { self.Gradient:GetPoint(2) }
	local topLinePosition = { self.TopLine:GetPoint() }
	local bottomLinePosition = { self.BottomLine:GetPoint() }
	local duration, elapsed = 1.0, 0.0

	local targetX, targetY = self:GetTargetOffsets(center)

	self:SetScript('OnUpdate', function(self, dt)
		elapsed = elapsed + dt
		local t = elapsed / duration
		gradientEndPoint[x] = Lerp(gradientEndPoint[x], -70, t)
		gradientEndPoint[y] = Lerp(gradientEndPoint[y], 120 + heightOffset, t)

		secondGradientPoint[x] = Lerp(secondGradientPoint[x], 70, t)
		secondGradientPoint[y] = Lerp(secondGradientPoint[y], -135, t)

		topLinePosition[y] = Lerp(topLinePosition[y], 0 + (heightOffset / 1.3), t)

		MainFramePosition[x] = Lerp(MainFramePosition[x], targetX, t)
		MainFramePosition[y] = Lerp(MainFramePosition[y], targetY, t)

		self:SetPoint(unpack(MainFramePosition))
		self.Gradient:SetPoint(unpack(gradientEndPoint))
		self.Gradient:SetPoint(unpack(secondGradientPoint))
		self.TopLine:SetPoint(unpack(topLinePosition))

		if ActiveSkin == 'Midnight' then
			bottomLinePosition[y] = Lerp(bottomLinePosition[y], -90, t)
			self.BottomLine:SetPoint(unpack(bottomLinePosition))
		else
			bottomLinePosition[y] = Lerp(bottomLinePosition[y], -50 + (heightOffset / 5), t)
			self.BottomLine:SetPoint(unpack(bottomLinePosition))
		end
		if t >= 1.0 then
			self:SetScript('OnUpdate', nil)
		end
	end)
end
