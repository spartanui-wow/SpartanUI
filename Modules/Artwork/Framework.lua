local SUI, L = SUI, SUI.L
---@class SUI.Module.Artwork : SUI.Module
local module = SUI:NewModule('Artwork')
module.ActiveStyle = {}
module.BarBG = {}
module.description = 'CORE: Provides the graphical looks of SUI'
module.Core = true
local styleArt
local petbattle = CreateFrame('FRAME')
-------------------------------------------------

local function SetupPage()
	local PageData = {
		ID = 'ArtworkCore',
		Name = 'SpartanUI style',
		SubTitle = 'Art Style',
		Desc1 = 'Please pick an art style from the options below.',
		Priority = true,
		RequireDisplay = (not SUI.DB.Artwork.SetupDone or false),
		Display = function()
			local SUI_Win = SUI.Setup.window.content
			local UI = LibAT.UI

			--Container
			SUI_Win.Artwork = CreateFrame('Frame', nil)
			SUI_Win.Artwork:SetParent(SUI_Win)
			SUI_Win.Artwork:SetAllPoints(SUI_Win)

			local RadioButtons = function(self)
				self.radio:Click()
			end
			local SetStyle = function(self)
				local NewStyle = UI.GetRadioGroupValue('SUIArtwork')
				if SUI.DB.Artwork.Style == NewStyle then
					return
				end

				SUI:SetActiveStyle(NewStyle)
			end

			local count = 0
			local row = 1
			local Themes = {}
			local width = 120
			for i, v in pairs({ 'Classic', 'War', 'Fel', 'Digital', 'Arcane', 'Minimal', 'Tribal', 'Transparent' }) do
				-- Create preview button
				local control = CreateFrame('Button', 'SETUPART_' .. v, SUI_Win.Artwork)
				control:SetSize(width, 60)
				control:SetNormalTexture('interface\\addons\\SpartanUI\\images\\setup\\Style_' .. v)
				control:SetHighlightAtlas('UI-CharacterCreate-LargeButton-Blue-Highlight', 'ADD')
				control:SetScript('OnClick', RadioButtons)

				-- Create radio button below preview
				control.radio = UI.CreateRadio(SUI_Win.Artwork, v, 'SUIArtwork', 120, 20)
				control.radio:SetValue(v)
				control.radio:HookScript('OnClick', SetStyle)
				control.radio:SetPoint('TOP', control, 'BOTTOM', 0, 0)
				if v == SUI.DB.Artwork.Style then
					control.radio:SetChecked(true)
				end

				Themes[i] = control

				count = count + 1
				if i == 1 then
					-- Position the 1st row
					control:SetPoint('TOP', SUI_Win, 'TOP', width * -1, -80)
				elseif count == 1 then
					control:SetPoint('TOP', Themes[i - 3], 'BOTTOM', 0, -30)
				elseif count == 2 then
					control:SetPoint('LEFT', Themes[i - 1], 'RIGHT', 20, 0)
				elseif count == 3 then
					control:SetPoint('LEFT', Themes[i - 1], 'RIGHT', 20, 0)

					row = row + 1
					count = 0
				end
			end

			local Popular = CreateFrame('Frame', nil, SUI_Win.Artwork, BackdropTemplateMixin and 'BackdropTemplate')
			Popular:SetPoint('TOPLEFT', 'SETUPART_Classic', 'TOPLEFT', -5, 5)
			Popular:SetPoint('BOTTOMRIGHT', 'SETUPART_War', 'BOTTOMRIGHT', 5, -25)

			Popular:SetBackdrop({
				bgFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
				edgeFile = 'Interface\\AddOns\\SpartanUI\\images\\blank.tga',
				edgeSize = 1,
			})
			Popular:SetBackdropColor(0.0588, 0.0588, 0, 0.85)
			Popular:SetBackdropBorderColor(0.9, 0.9, 0, 0.9)
			Popular.lbl = UI.CreateLabel(SUI_Win.Artwork, 'Popular', 'GameFontNormal')
			Popular.lbl:SetPoint('BOTTOMLEFT', Popular, 'TOPLEFT', 0, 0)

			SUI_Win.Artwork.Popular = Popular

			-- UI Scale slider
			SUI_Win.Artwork.slider = UI.CreateSlider(SUI_Win.Artwork, 340, 15, 50, 100, 1)
			SUI_Win.Artwork.slider:SetPoint('TOP', SUI_Win.Artwork, 'TOP', 0, -30)

			-- Slider label
			local sliderLabel = UI.CreateLabel(SUI_Win.Artwork, 'UI Scale', 'GameFontNormal')
			sliderLabel:SetPoint('RIGHT', SUI_Win.Artwork.slider, 'LEFT', -5, 0)

			-- Slider value display
			SUI_Win.Artwork.sliderText = UI.CreateEditBox(SUI_Win.Artwork, 40, 15)
			SUI_Win.Artwork.sliderText:SetPoint('LEFT', SUI_Win.Artwork.slider, 'RIGHT', 5, 0)
			SUI_Win.Artwork.sliderText:Disable()

			-- Slider reset button
			SUI_Win.Artwork.sliderButton = UI.CreateButton(SUI_Win.Artwork, 40, 15, 'reset')
			SUI_Win.Artwork.sliderButton:SetPoint('LEFT', SUI_Win.Artwork.sliderText, 'RIGHT', 5, 0)

			-- Slider Actions
			SUI_Win.Artwork.slider:SetScript('OnValueChanged', function(self)
				local calculate = SUI_Win.Artwork.slider:GetValue()
				if math.floor(calculate) ~= math.floor(calculate) then
					SUI_Win.Artwork.slider:SetValue(math.floor(calculate))
					return
				end

				local scale = math.floor(SUI_Win.Artwork.slider:GetValue()) / 100
				SUI_Win.Artwork.sliderText:SetText(scale)

				SUI.DB.scale = scale

				-- Update screen
				module:UpdateScale()

				if scale ~= 0.92 then
					SUI_Win.Artwork.sliderButton:Enable()
					SUI_Win.Artwork.sliderButton:Show()
				else
					SUI_Win.Artwork.sliderButton:Disable()
					SUI_Win.Artwork.sliderButton:Hide()
				end
			end)
			SUI_Win.Artwork.sliderButton:SetScript('OnClick', function()
				SUI_Win.Artwork.slider:SetValue(92)
			end)
			SUI_Win.Artwork.slider:SetValue(SUI.DB.scale * 100)
		end,
		Next = function()
			SUI.DB.Artwork.SetupDone = true
		end,
	}
	SUI.Setup:AddPage(PageData)
end

local function StyleUpdate()
	if InCombatLockdown() then
		return
	end

	module:UpdateScale()
	module:UpdateAlpha()
	module:updateOffset()
	module:updateHorizontalOffset()
	module:updateViewport()
	module:UpdateBarBG()
end

function module:SetActiveStyle(style)
	if style and style ~= SUI.DB.Artwork.Style then
		-- Cache the styles to swap
		local OldStyle = SUI:GetModule('Style.' .. SUI.DB.Artwork.Style)
		local NewStyle = SUI:GetModule('Style.' .. style)

		-- Update the DB
		SUI.DB.Artwork.Style = style

		-- Disable the current style and enable the one we want
		OldStyle:Disable()
		NewStyle:Enable()

		--Update bars
		SUI.Handlers.BarSystem.Refresh()

		--Update minimap
		local minimapModule = SUI:GetModule('Minimap') ---@type SUI.Module.Minimap
		if minimapModule then
			minimapModule:SetActiveStyle(style)
		end

		--Update statusbar
		local StatusBars = SUI:GetModule('Artwork.StatusBars') ---@type SUI.Module.Artwork.StatusBars
		if StatusBars then
			StatusBars:SetActiveStyle(style)
		end

		--Update UnitFrames
		if SUI.UF and SUI.UF.Style then
			SUI.UF.Style:Change(style)
		end
	end

	-- Update style settings shortcut
	module.ActiveStyle = SUI.DB.Styles[SUI.DB.Artwork.Style]
	styleArt = _G['SUI_Art_' .. SUI.DB.Artwork.Style]

	--Send Custom change event
	SUI.Event:SendEvent('ARTWORK_STYLE_CHANGED')

	-- Update core elements based on new style
	StyleUpdate()
end

function module:UpdateScale()
	-- Set overall UI scale
	SpartanUI:SetScale(SUI.DB.scale)

	-- Call style scale update if defined.
	local style = SUI:GetModule('Style.' .. SUI.DB.Artwork.Style)
	if style.UpdateScale then
		style:UpdateScale()
	end
	if SUI:IsModuleEnabled('UnitFrames') then
		SUI.UF:ScaleFrames(SUI.DB.scale)
	end

	-- Call Minimap scale update
	local minimap = SUI:GetModule('Minimap', true) ---@type SUI.Module.Minimap
	if minimap and minimap.Settings and minimap.Settings.scaleWithArt then
		minimap:UpdateScale()
	end

	-- Update Bar scales
	SUI.Handlers.BarSystem:Refresh()
end

function module:UpdateAlpha()
	if styleArt then
		styleArt:SetAlpha(SUI.DB.alpha)
	end
	-- Call module scale update if defined.
	local style = SUI:GetModule('Style.' .. SUI.DB.Artwork.Style)
	if style.UpdateAlpha then
		style:UpdateAlpha()
	end
end

function module:updateOffset()
	if InCombatLockdown() then
		return
	end

	SUI.Log('updateOffset called - TopAuto: ' .. tostring(SUI.DB.Artwork.Offset.TopAuto) .. ', BottomAuto: ' .. tostring(SUI.DB.Artwork.Offset.BottomAuto), 'Artwork', 'debug')

	local Top, Bottom = 0, 0
	local Tfubar, TChocolateBar, Ttitan, TLibsDataBar = 0, 0, 0, 0
	local Bfubar, BChocolateBar, Btitan, BLibsDataBar = 0, 0, 0, 0
	local SUITopOffset, SUIBottomOffset = 0, 0

	if SUI.DB.Artwork.Offset.TopAuto or SUI.DB.Artwork.Offset.BottomAuto then
		-- FuBar Offset
		for i = 1, 4 do
			local bar = _G['FuBarFrame' .. i]
			if bar and bar:IsVisible() then
				local point = bar:GetPoint(1)
				if point:find('TOP.*') then
					Tfubar = Tfubar + bar:GetHeight()
				end
				if point == 'BOTTOMLEFT' then
					Bfubar = Bfubar + bar:GetHeight()
				end
			end
		end

		-- Chocolate Bar Offset
		for i = 1, 100 do
			local bar = _G['ChocolateBar' .. i]
			if bar and bar:IsVisible() then
				local point = bar:GetPoint(1)
				if point:find('TOP.*') then
					TChocolateBar = TChocolateBar + bar:GetHeight()
				end
				if point == 'RIGHT' then
					BChocolateBar = BChocolateBar + bar:GetHeight()
				end
			end
		end

		-- Titan Bar
		local TitanBars = { ['Bar2'] = 'top', ['Bar'] = 'top', ['AuxBar2'] = 'bottom', ['AuxBar'] = 'bottom' }
		for k, v in pairs(TitanBars) do
			local bar = _G['Titan_Bar__Display_' .. k]
			if bar and bar:IsVisible() then
				if v == 'top' then
					Ttitan = Ttitan + ((TitanPanelGetVar('Scale') or 1) * bar:GetHeight())
				else
					Btitan = Btitan + ((TitanPanelGetVar('Scale') or 1) * bar:GetHeight())
				end
			end
		end

		-- LibsDataBar Detection
		if LibsDataBar and LibsDataBar.API then
			local ldbOffsets = LibsDataBar.API:GetBarOffsets()
			if ldbOffsets then
				TLibsDataBar = ldbOffsets.top or 0
				BLibsDataBar = ldbOffsets.bottom or 0
				SUI.Log('LibsDataBar offsets detected - top: ' .. TLibsDataBar .. ', bottom: ' .. BLibsDataBar, 'Artwork', 'debug')
			end
		else
			SUI.Log('LibsDataBar.API not available', 'Artwork', 'debug')
		end

		-- Blizz Legion Order Hall
		if OrderHallCommandBar and OrderHallCommandBar:IsVisible() then
			Top = Top + OrderHallCommandBar:GetHeight()
		end

		-- Calculate SUI's own offset (excluding LibsDataBar - we'll add that separately)
		SUITopOffset = max(Top + Tfubar + Ttitan + TChocolateBar, 0)
		SUIBottomOffset = max(Bottom + Bfubar + Btitan + BChocolateBar, 0)

		-- Update DB if set to auto (total offset including LibsDataBar)
		if SUI.DB.Artwork.Offset.TopAuto then
			SUI.DB.Artwork.Offset.Top = max(SUITopOffset + TLibsDataBar, 0)
		end
		if SUI.DB.Artwork.Offset.BottomAuto then
			SUI.DB.Artwork.Offset.Bottom = max(SUIBottomOffset + BLibsDataBar, 0)
		end
	end

	-- Call module update if defined.
	local style = SUI:GetModule('Style.' .. SUI.DB.Artwork.Style)
	if style.updateOffset then
		style:updateOffset(SUI.DB.Artwork.Offset.Top, SUI.DB.Artwork.Offset.Bottom)
	end

	SpartanUI:ClearAllPoints()
	SpartanUI:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', 0, (SUI.DB.Artwork.Offset.Top * -1))
	if SUI.DB.Artwork.Offset.BottomAuto and _G['TitanPanelBottomAnchor'] then
		SpartanUI:SetPoint('BOTTOMLEFT', _G['TitanPanelBottomAnchor'], 'BOTTOMLEFT', 0, 0)
	else
		SpartanUI:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 0, SUI.DB.Artwork.Offset.Bottom)
	end

	-- LibsDataBar integration is ONE-WAY:
	-- SUI reads LibsDataBar's bar offsets (done above) and adjusts artwork accordingly
	-- LibsDataBar does NOT need to know about SUI - it positions itself based on config only
end

function module:updateHorizontalOffset()
	SUI_BottomAnchor:ClearAllPoints()
	SUI_BottomAnchor:SetPoint('BOTTOM', SpartanUI, 'BOTTOM', SUI.DB.Artwork.Offset.Horizontal.Bottom, 0)

	SUI_TopAnchor:ClearAllPoints()
	SUI_TopAnchor:SetPoint('TOP', SpartanUI, 'TOP', SUI.DB.Artwork.Offset.Horizontal.Top, 0)

	-- Call module scale update if defined.
	local style = SUI:GetModule('Style.' .. SUI.DB.Artwork.Style)
	if style.updateXOffset then
		style:updateXOffset()
	end
end

function module:updateViewport()
	-- Defensive check: ensure Viewport exists in profile (might be missing after profile swap)
	if not SUI.DB.Artwork or not SUI.DB.Artwork.Viewport then
		return
	end

	if not InCombatLockdown() and SUI.DB.Artwork.Viewport.enabled then
		WorldFrame:ClearAllPoints()
		WorldFrame:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', SUI.DB.Artwork.Viewport.offset.left, (SUI.DB.Artwork.Viewport.offset.top * -1))
		WorldFrame:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', (SUI.DB.Artwork.Viewport.offset.right * -1), SUI.DB.Artwork.Viewport.offset.bottom)
	end
end

function module:OnInitialize()
	if SUI:IsModuleDisabled('Artwork') then
		return
	end

	-- Register for sequential profile refresh (Artwork doesn't use RegisterNamespace, uses SUI.DB.Artwork directly)
	-- We create a dummy Database object just for the refresh system
	module.Database = { profile = SUI.DB.Artwork }
	SUI.DBM:RegisterSequentialProfileRefresh(module, 'RefreshViewport')

	-- Setup options
	module:SetupOptions()

	-- Initalize style
	module:SetActiveStyle()

	-- Register theme textures with LibSharedMedia
	module:RegisterThemeTextures()

	-- Loop over the BlizzMovers and execute them
	module.BlizzMovers()
end

local function VehicleUI()
	if SUI.DB.Artwork.VehicleUI then
		local minimapModule = SUI:GetModule('Minimap', true)
		local artFrame = _G['SUI_Art_' .. SUI.DB.Artwork.Style]

		petbattle:HookScript('OnHide', function()
			if InCombatLockdown() then
				return
			end
			if artFrame then
				artFrame:Hide()
			end
			if SUI:IsModuleEnabled('Minimap') and (minimapModule.DB.AutoDetectAllowUse or minimapModule.DB.ManualAllowUse) then
				Minimap:Hide()
			end
		end)
		petbattle:HookScript('OnShow', function()
			if InCombatLockdown() then
				return
			end
			if artFrame then
				artFrame:Show()
			end
			if SUI:IsModuleEnabled('Minimap') and (minimapModule.DB.AutoDetectAllowUse or minimapModule.DB.ManualAllowUse) then
				Minimap:Show()
			end
		end)
		RegisterStateDriver(SpartanUI, 'visibility', '[petbattle][overridebar][vehicleui] hide; show')
	end
end

---Refresh viewport settings from new profile
function module:RefreshViewport()
	-- Note: Artwork uses SUI.DB.Artwork directly, not module.DB
	-- The sequential refresh system already updated SUI.DB reference in UpdateModuleConfigs

	-- Re-apply viewport settings from new profile
	if SUI.DB.Artwork and SUI.DB.Artwork.Viewport then
		module:updateViewport()
	end

	-- Don't call SetActiveStyle here - UpdateModuleConfigs handles it sequentially
end

function module:OnEnable()
	if SUI:IsModuleDisabled('Artwork') then
		return
	end

	if SUI.Handlers.BarSystem then
		SUI.Handlers.BarSystem.Refresh()
	end

	SetupPage()
	VehicleUI()
	StyleUpdate()
	module:RegisterEvent('ADDON_LOADED', StyleUpdate)
	module:RegisterEvent('PLAYER_ENTERING_WORLD', StyleUpdate)

	-- Register with LibsDataBar API if available
	local function tryRegisterIntegration()
		if _G.LibsDataBar_RegisterIntegration then
			_G.LibsDataBar_RegisterIntegration('SpartanUI', function(event, data)
				if event == 'refresh' or event == 'resize' or event == 'move' or event == 'show' or event == 'hide' then
					module:updateOffset()
				end
			end)
			SUI.Log('LibsDataBar integration registered successfully', 'Artwork')
		else
			-- LibsDataBar not available yet, retry
			C_Timer.After(1, tryRegisterIntegration)
		end
	end

	-- Start registration attempts after a delay
	C_Timer.After(2, tryRegisterIntegration)
end

function module:UpdateBarBG()
	if not module.BarBG[SUI.DB.Artwork.Style] then
		return
	end
	local usersettings = module.ActiveStyle.Artwork.barBG
	for i, bgFrame in pairs(module.BarBG[SUI.DB.Artwork.Style]) do
		if usersettings[i] then
			if usersettings[i].enabled then
				bgFrame:Show()
				bgFrame.BG:Show()

				-- Keep background in normal position - borders will extend outside
				-- Reset background to default positioning first
				bgFrame.BG:ClearAllPoints()
				if bgFrame.skinSettings.point then
					bgFrame.BG:SetPoint(bgFrame.skinSettings.point)
				else
					bgFrame.BG:SetAllPoints(bgFrame)
				end

				-- Handle different background types
				local bgType = usersettings[i].bgType or 'texture'
				if bgType == 'color' then
					-- Solid color background
					local color
					if usersettings[i].classColorBG then
						-- Use class color for background
						local _, class = UnitClass('player')
						local classColor = RAID_CLASS_COLORS[class]
						if classColor then
							color = { classColor.r, classColor.g, classColor.b, 1 }
						else
							color = usersettings[i].backgroundColor or { 0, 0, 0, 1 }
						end
					else
						color = usersettings[i].backgroundColor or { 0, 0, 0, 1 }
					end
					bgFrame.BG:SetColorTexture(color[1], color[2], color[3], color[4] * usersettings[i].alpha)
				elseif bgType == 'custom' then
					-- Custom texture from LibSharedMedia
					local LSM = LibStub('LibSharedMedia-3.0')
					local texture = usersettings[i].customTexture or 'Blizzard'
					bgFrame.BG:SetTexture(LSM:Fetch('statusbar', texture))
					bgFrame.BG:SetAlpha((bgFrame.skinSettings.alpha or 1) * usersettings[i].alpha)

					-- Apply texture color/tint
					local useSkinColors = usersettings[i].useSkinColors ~= false -- Default to true
					if usersettings[i].classColorBG then
						-- Use class color for background texture
						local _, class = UnitClass('player')
						local classColor = RAID_CLASS_COLORS[class]
						if classColor then
							bgFrame.BG:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
						else
							local skinColor = bgFrame.skinSettings.color or { 1, 1, 1, 1 }
							bgFrame.BG:SetVertexColor(skinColor[1], skinColor[2], skinColor[3], skinColor[4])
						end
					elseif not useSkinColors and usersettings[i].textureColor then
						-- Use custom user color
						local textureColor = usersettings[i].textureColor
						bgFrame.BG:SetVertexColor(textureColor[1], textureColor[2], textureColor[3], textureColor[4])
					else
						-- Use default/skin colors (for custom textures, default to white)
						local skinColor = bgFrame.skinSettings.color or { 1, 1, 1, 1 }
						bgFrame.BG:SetVertexColor(skinColor[1], skinColor[2], skinColor[3], skinColor[4])
					end
				else
					-- Default theme texture
					bgFrame.BG:SetTexture(bgFrame.skinSettings.TexturePath)
					bgFrame.BG:SetTexCoord(unpack(bgFrame.skinSettings.TexCoord or { 0, 1, 0, 1 }))
					bgFrame.BG:SetAlpha((bgFrame.skinSettings.alpha or 1) * usersettings[i].alpha)

					-- Apply texture color/tint or use skin defaults
					local useSkinColors = usersettings[i].useSkinColors ~= false -- Default to true
					if usersettings[i].classColorBG then
						-- Use class color for background texture
						local _, class = UnitClass('player')
						local classColor = RAID_CLASS_COLORS[class]
						if classColor then
							bgFrame.BG:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
						else
							local skinColor = bgFrame.skinSettings.color or { 1, 1, 1, 1 }
							bgFrame.BG:SetVertexColor(skinColor[1], skinColor[2], skinColor[3], skinColor[4])
						end
					elseif not useSkinColors and usersettings[i].textureColor then
						-- Use custom user color
						local textureColor = usersettings[i].textureColor
						bgFrame.BG:SetVertexColor(textureColor[1], textureColor[2], textureColor[3], textureColor[4])
					else
						-- Use skin-defined colors or default
						local skinColor = bgFrame.skinSettings.color or { 1, 1, 1, 1 }
						bgFrame.BG:SetVertexColor(skinColor[1], skinColor[2], skinColor[3], skinColor[4])
					end
				end

				-- Handle borders with individual side support
				if usersettings[i].borderEnabled then
					-- Initialize border container if not exists
					if not bgFrame.Borders then
						bgFrame.Borders = {}
					end

					local borderSize = usersettings[i].borderSize or 1
					local borderColors = usersettings[i].borderColors or {}
					local borderSides = usersettings[i].borderSides or { top = true, bottom = true, left = true, right = true }

					-- Create/update individual border sides
					local sides = { 'top', 'bottom', 'left', 'right' }
					for _, side in ipairs(sides) do
						if borderSides[side] then
							-- Create border side if it doesn't exist
							if not bgFrame.Borders[side] then
								bgFrame.Borders[side] = CreateFrame('Frame', nil, bgFrame:GetParent())
								bgFrame.Borders[side]:SetFrameLevel(bgFrame:GetFrameLevel() + 1) -- Above background
								bgFrame.Borders[side].texture = bgFrame.Borders[side]:CreateTexture(nil, 'ARTWORK')
								bgFrame.Borders[side].texture:SetTexture('Interface\\Buttons\\WHITE8X8')
							end

							-- Get individual border color for this side
							local sideColor = borderColors[side] or { 1, 1, 1, 1 }

							-- Use class color if enabled for this specific side
							local classColorBorders = usersettings[i].classColorBorders or {}
							if classColorBorders[side] then
								local _, class = UnitClass('player')
								local classColor = RAID_CLASS_COLORS[class]
								if classColor then
									sideColor = { classColor.r, classColor.g, classColor.b, sideColor[4] or 1 }
								end
							end

							-- Position border sides outside the background frame
							-- Horizontal borders (top/bottom) extend to cover vertical border areas for proper corners
							local border = bgFrame.Borders[side]
							border:ClearAllPoints()

							if side == 'top' then
								-- Extend left/right to cover vertical border areas
								local leftExtend = (borderSides.left and borderSize) or 0
								local rightExtend = (borderSides.right and borderSize) or 0
								border:SetPoint('BOTTOMLEFT', bgFrame, 'TOPLEFT', -leftExtend, 0)
								border:SetPoint('BOTTOMRIGHT', bgFrame, 'TOPRIGHT', rightExtend, 0)
								border:SetHeight(borderSize)
							elseif side == 'bottom' then
								-- Extend left/right to cover vertical border areas
								local leftExtend = (borderSides.left and borderSize) or 0
								local rightExtend = (borderSides.right and borderSize) or 0
								border:SetPoint('TOPLEFT', bgFrame, 'BOTTOMLEFT', -leftExtend, 0)
								border:SetPoint('TOPRIGHT', bgFrame, 'BOTTOMRIGHT', rightExtend, 0)
								border:SetHeight(borderSize)
							elseif side == 'left' then
								-- Don't extend vertically - horizontal borders will cover corners
								border:SetPoint('TOPRIGHT', bgFrame, 'TOPLEFT', 0, 0)
								border:SetPoint('BOTTOMRIGHT', bgFrame, 'BOTTOMLEFT', 0, 0)
								border:SetWidth(borderSize)
							elseif side == 'right' then
								-- Don't extend vertically - horizontal borders will cover corners
								border:SetPoint('TOPLEFT', bgFrame, 'TOPRIGHT', 0, 0)
								border:SetPoint('BOTTOMLEFT', bgFrame, 'BOTTOMRIGHT', 0, 0)
								border:SetWidth(borderSize)
							end

							border.texture:SetAllPoints(border)
							border.texture:SetColorTexture(sideColor[1], sideColor[2], sideColor[3], sideColor[4])
							border:Show()
						elseif bgFrame.Borders[side] then
							-- Hide unused border sides
							bgFrame.Borders[side]:Hide()
						end
					end
				elseif bgFrame.Borders then
					-- Hide all border sides and reset background positioning
					for _, side in ipairs({ 'top', 'bottom', 'left', 'right' }) do
						if bgFrame.Borders[side] then
							bgFrame.Borders[side]:Hide()
						end
					end
					-- Reset background to default positioning when borders are disabled
					bgFrame.BG:ClearAllPoints()
					if bgFrame.skinSettings.point then
						bgFrame.BG:SetPoint(bgFrame.skinSettings.point)
					else
						bgFrame.BG:SetAllPoints(bgFrame)
					end
				end
			else
				bgFrame:Hide()
				bgFrame.BG:Hide()
				if bgFrame.Border then
					bgFrame.Border:Hide()
				end
				if bgFrame.Borders then
					for _, side in ipairs({ 'top', 'bottom', 'left', 'right' }) do
						if bgFrame.Borders[side] then
							bgFrame.Borders[side]:Hide()
						end
					end
				end
				-- Reset background positioning when disabled
				bgFrame.BG:ClearAllPoints()
				if bgFrame.skinSettings.point then
					bgFrame.BG:SetPoint(bgFrame.skinSettings.point)
				else
					bgFrame.BG:SetAllPoints(bgFrame)
				end
			end
		end
	end
end

function module:CreateBarBG(skinSettings, number, parent)
	local frame = CreateFrame('Frame', skinSettings.name .. '_Bar' .. number, (parent or UIParent))
	frame.skinSettings = skinSettings
	frame:SetFrameStrata('BACKGROUND')
	frame:SetSize((skinSettings.width or 400), (skinSettings.height or 32))
	frame.BG = frame:CreateTexture(skinSettings.name .. '_Bar' .. number .. 'BG', 'BACKGROUND')
	frame.BG:SetTexture(skinSettings.TexturePath)
	frame.BG:SetTexCoord(unpack(skinSettings.TexCoord or { 0, 1, 0, 1 }))
	frame.BG:SetAlpha(skinSettings.alpha or 1)
	if skinSettings.point then
		frame.BG:SetPoint(skinSettings.point)
	else
		frame.BG:SetAllPoints(frame)
	end

	if not module.BarBG[skinSettings.name] then
		module.BarBG[skinSettings.name] = {}
	end
	module.BarBG[skinSettings.name][tostring(number)] = frame

	module:UpdateBarBG()

	return frame
end

---Register theme textures with LibSharedMedia for use in custom backgrounds
function module:RegisterThemeTextures()
	local LSM = SUI.Lib.LSM
	if not LSM then
		return
	end

	-- -- Define theme texture mappings
	-- local themeTextures = {
	-- 	War = {
	-- 		{ name = 'SUI War - StatusBar Alliance', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\StatusBar-Alliance.blp' },
	-- 		{ name = 'SUI War - StatusBar Horde', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\StatusBar-Horde.blp' },
	-- 		{ name = 'SUI War - StatusBar Neutral', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\StatusBar-Neutral.blp' },
	-- 		{ name = 'SUI War - Bar Background', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\Barbg.blp' },
	-- 		{ name = 'SUI War - Bar Background Alliance', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\Barbg-Alliance.blp' },
	-- 		{ name = 'SUI War - Bar Background Horde', file = 'Interface\\AddOns\\SpartanUI\\Themes\\War\\Images\\Barbg-Horde.blp' },
	-- 	},
	-- 	Fel = {
	-- 		{ name = 'SUI Fel - StatusBar', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\StatusBar.png' },
	-- 		{ name = 'SUI Fel - Status Fill', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Status_bar_Fill.blp' },
	-- 	},
	-- 	Tribal = {
	-- 		{ name = 'SUI Tribal - StatusBar', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\images\\Statusbar.blp' },
	-- 		{ name = 'SUI Tribal - Bar Background', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Tribal\\images\\Barbg.tga' },
	-- 	},
	-- 	Digital = {
	-- 		{ name = 'SUI Digital - Bar Background', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Digital\\Images\\BarBG.blp' },
	-- 	},
	-- 	Classic = {
	-- 		{ name = 'SUI Classic - Bar Backdrop 0', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Classic\\Images\\bar-backdrop0.blp' },
	-- 		{ name = 'SUI Classic - Bar Backdrop 1', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Classic\\Images\\bar-backdrop1.blp' },
	-- 		{ name = 'SUI Classic - Bar Backdrop 3', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Classic\\Images\\bar-backdrop3.blp' },
	-- 	},
	-- 	Minimal = {
	-- 		{ name = 'SUI Minimal - Bar Backdrop 1', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Minimal\\Images\\bar-backdrop1.blp' },
	-- 		{ name = 'SUI Minimal - Bar Backdrop 3', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Minimal\\Images\\bar-backdrop3.blp' },
	-- 	},
	-- 	Transparent = {
	-- 		{ name = 'SUI Transparent - Bar Backdrop 0', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Transparent\\Images\\bar-backdrop0.blp' },
	-- 		{ name = 'SUI Transparent - Bar Backdrop 1', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Transparent\\Images\\bar-backdrop1.blp' },
	-- 		{ name = 'SUI Transparent - Bar Backdrop 3', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Transparent\\Images\\bar-backdrop3.blp' },
	-- 	},
	-- 	Arcane = {
	-- 		{ name = 'SUI Arcane - StatusBar', file = 'Interface\\AddOns\\SpartanUI\\Themes\\Arcane\\Images\\StatusBar.tga' },
	-- 	},
	-- }

	-- -- Register all textures with LibSharedMedia
	-- for themeName, textures in pairs(themeTextures) do
	-- 	for _, texture in pairs(textures) do
	-- 		LSM:Register('statusbar', texture.name, texture.file)
	-- 	end
	-- end
end
