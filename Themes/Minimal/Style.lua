local SUI, L = SUI, SUI.L
---@class SUI.Theme.Minimal : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Minimal')
local Artwork_Core = SUI:GetModule('Artwork') ---@type SUI.Module.Artwork
local unpack = unpack
----------------------------------------------------------------------------------------------------

function module:OnInitialize()
	SUI.ThemeRegistry:Register({
		name = 'Minimal',
		displayName = 'Minimal',
		apiVersion = 1,
		description = 'Clean minimal interface with configurable artwork panels',
		setup = {
			image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Minimal',
		},
		applicableTo = {},
	}, function()
		return {
			color = {
				Art = {
					0.6156862745098039,
					0.1215686274509804,
					0.1215686274509804,
					0.9,
				},
			},
			options = {
				HideCenterGraphic = false,
				HideTopLeft = false,
				HideTopRight = false,
				HideBottomLeft = false,
				HideBottomRight = false,
				UseClassColors = false,
			},
			barPositions = {
				['BT4Bar1'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-1,90',
				['BT4Bar2'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-1,45',
				--
				['BT4Bar3'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,1,1',
				['BT4Bar4'] = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOMRIGHT,1,1',
				--
				['BT4Bar5'] = 'BOTTOMRIGHT,SUI_BottomAnchor,BOTTOM,-232,1',
				['BT4Bar6'] = 'BOTTOMLEFT,SUI_BottomAnchor,BOTTOM,260,1',
				--
				['BT4BarExtraActionBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,130',
				['BT4BarZoneAbilityBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,0,130',
				--
				['BT4BarStanceBar'] = 'TOP,SpartanUI,TOP,-301,0',
				['BT4BarPetBar'] = 'TOP,SpartanUI,TOP,-558,0',
				['MultiCastActionBarFrame'] = 'TOP,SpartanUI,TOP,-558,0',
				--
				['BT4BarMicroMenu'] = 'TOP,SpartanUI,TOP,322,0',
				['BT4BarBagBar'] = 'TOP,SpartanUI,TOP,595,0',
			},
			barScales = {
				['BT4Bar1'] = 0.78,
				['BT4Bar2'] = 0.78,
				['BT4Bar3'] = 0.78,
				['BT4Bar4'] = 0.78,
				['BT4Bar5'] = 0.78,
				['BT4Bar6'] = 0.7,
				['BT4Bar7'] = 0.7,
				['BT4Bar8'] = 0.78,
				['BT4Bar9'] = 0.78,
				['BT4Bar10'] = 0.78,
				['BT4BarBagBar'] = 0.6,
				['BT4BarExtraActionBar'] = 0.8,
				['BT4BarStanceBar'] = 0.6,
				['BT4BarPetBar'] = 0.6,
				['MultiCastActionBarFrame'] = 0.6,
				['BT4BarMicroMenu'] = 0.6,
			},
			minimap = SUI.IsRetail and {
				UnderVehicleUI = false,
				scaleWithArt = false,
				position = 'TOPRIGHT,SUI_Art_Minimal_Base3,TOPRIGHT,-10,-10',
				shape = 'square',
				size = { 180, 180 },
				elements = {
					background = {
						enabled = false,
					},
				},
			} or {
				UnderVehicleUI = false,
				scaleWithArt = false,
				position = 'TOPRIGHT,SUI_Art_Minimal_Base3,TOPRIGHT,-10,-10',
				shape = 'square',
				size = { 140, 140 },
				background = {
					enabled = false,
				},
			},
			unitframes = {
				displayName = 'Minimal',
				setup = {
					image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Minimal',
				},
			},
		}
	end)
end

function module:OnEnable()
	if SUI:GetActiveStyle() ~= 'Minimal' then
		module:Disable()
	else
		module:Options()

		hooksecurefunc('UIParent_ManageFramePositions', function()
			if TutorialFrameAlertButton then
				TutorialFrameAlertButton:SetParent(Minimap)
				TutorialFrameAlertButton:ClearAllPoints()
				TutorialFrameAlertButton:SetPoint('CENTER', Minimap, 'TOP', -2, 30)
			end
			if CastingBarFrame then
				CastingBarFrame:ClearAllPoints()
				CastingBarFrame:SetPoint('BOTTOM', SUI_Art_Minimal_Base1, 'TOP', 0, 90)
			end
		end)

		--Setup Sliding Trays
		module:SlidingTrays()
		if BT4BarBagBar and BT4BarPetBar.position then
			BT4BarPetBar:position('TOPLEFT', 'SlidingTray_left', 'TOPLEFT', 50, -2)
			BT4BarStanceBar:position('TOPRIGHT', 'SlidingTray_left', 'TOPRIGHT', -50, -2)
			BT4BarMicroMenu:position('TOPLEFT', 'SlidingTray_right', 'TOPLEFT', 50, -2)
			BT4BarBagBar:position('TOPRIGHT', 'SlidingTray_right', 'TOPRIGHT', -100, -2)
		end

		module:SetColor()

		-- Show or hide individual elements based on settings
		if SUI.ThemeRegistry:GetSetting('Minimal', 'HideCenterGraphic') then
			SUI_Art_Minimal_Base1:Hide()
		else
			SUI_Art_Minimal_Base1:Show()
		end

		if SUI.ThemeRegistry:GetSetting('Minimal', 'HideTopLeft') then
			SUI_Art_Minimal_Base2:Hide()
		else
			SUI_Art_Minimal_Base2:Show()
		end

		if SUI.ThemeRegistry:GetSetting('Minimal', 'HideTopRight') then
			SUI_Art_Minimal_Base3:Hide()
		else
			SUI_Art_Minimal_Base3:Show()
		end

		if SUI.ThemeRegistry:GetSetting('Minimal', 'HideBottomLeft') then
			SUI_Art_Minimal_Base4:Hide()
		else
			SUI_Art_Minimal_Base4:Show()
		end

		if SUI.ThemeRegistry:GetSetting('Minimal', 'HideBottomRight') then
			SUI_Art_Minimal_Base5:Hide()
		else
			SUI_Art_Minimal_Base5:Show()
		end

		SUI_Art_Minimal:Show()
	end
end

function module:TooltipLoc(tooltip, parent)
	if parent == 'UIParent' then
		tooltip:ClearAllPoints()
		tooltip:SetPoint('BOTTOMRIGHT', SUI_Art_Minimal, 'BOTTOMRIGHT', -20, 20)
	end
end

function module:Options()
	SUI.opt.args['Artwork'].args['Art'] = {
		name = L['Artwork Options'],
		type = 'group',
		order = 10,
		args = {
			HideCenterGraphic = {
				name = L['Hide center graphic'],
				type = 'toggle',
				order = 1,
				get = function(info)
					return SUI.ThemeRegistry:GetSetting('Minimal', 'HideCenterGraphic')
				end,
				set = function(info, val)
					SUI.ThemeRegistry:SetSetting('Minimal', 'HideCenterGraphic', val)
					if SUI.ThemeRegistry:GetSetting('Minimal', 'HideCenterGraphic') then
						SUI_Art_Minimal_Base1:Hide()
					else
						SUI_Art_Minimal_Base1:Show()
					end
				end,
			},
			HideTopLeft = {
				name = L['Hide Top Left'],
				type = 'toggle',
				order = 2,
				get = function(info)
					return SUI.ThemeRegistry:GetSetting('Minimal', 'HideTopLeft')
				end,
				set = function(info, val)
					SUI.ThemeRegistry:SetSetting('Minimal', 'HideTopLeft', val)
					if SUI.ThemeRegistry:GetSetting('Minimal', 'HideTopLeft') then
						SUI_Art_Minimal_Base2:Hide()
					else
						SUI_Art_Minimal_Base2:Show()
					end
				end,
			},
			HideTopRight = {
				name = L['Hide Top Right'],
				type = 'toggle',
				order = 3,
				get = function(info)
					return SUI.ThemeRegistry:GetSetting('Minimal', 'HideTopRight')
				end,
				set = function(info, val)
					SUI.ThemeRegistry:SetSetting('Minimal', 'HideTopRight', val)
					if SUI.ThemeRegistry:GetSetting('Minimal', 'HideTopRight') then
						SUI_Art_Minimal_Base3:Hide()
					else
						SUI_Art_Minimal_Base3:Show()
					end
				end,
			},
			HideBottomLeft = {
				name = L['Hide Bottom Left'],
				type = 'toggle',
				order = 4,
				get = function(info)
					return SUI.ThemeRegistry:GetSetting('Minimal', 'HideBottomLeft')
				end,
				set = function(info, val)
					SUI.ThemeRegistry:SetSetting('Minimal', 'HideBottomLeft', val)
					if SUI.ThemeRegistry:GetSetting('Minimal', 'HideBottomLeft') then
						SUI_Art_Minimal_Base4:Hide()
					else
						SUI_Art_Minimal_Base4:Show()
					end
				end,
			},
			HideBottomRight = {
				name = L['Hide Bottom Right'],
				type = 'toggle',
				order = 5,
				get = function(info)
					return SUI.ThemeRegistry:GetSetting('Minimal', 'HideBottomRight')
				end,
				set = function(info, val)
					SUI.ThemeRegistry:SetSetting('Minimal', 'HideBottomRight', val)
					if SUI.ThemeRegistry:GetSetting('Minimal', 'HideBottomRight') then
						SUI_Art_Minimal_Base5:Hide()
					else
						SUI_Art_Minimal_Base5:Show()
					end
				end,
			},
			UseClassColors = {
				name = L['Use Class Colors'],
				type = 'toggle',
				order = 6,
				desc = L['Use your class colors for artwork instead of custom colors'],
				get = function(info)
					return SUI.ThemeRegistry:GetSetting('Minimal', 'UseClassColors')
				end,
				set = function(info, val)
					SUI.ThemeRegistry:SetSetting('Minimal', 'UseClassColors', val)
					module:SetColor()
				end,
			},
			alpha = {
				name = L['Artwork Color'],
				type = 'color',
				hasAlpha = true,
				order = 7,
				width = 'full',
				desc = L['XP and Rep Bars are known issues and need a redesign to look right'],
				hidden = function(info)
					return SUI.ThemeRegistry:GetSetting('Minimal', 'UseClassColors')
				end,
				get = function(info)
					local art = SUI.ThemeRegistry:GetSetting('Minimal', 'Color.Art')
					if art then
						return unpack(art)
					end
					return 1, 1, 1, 1
				end,
				set = function(info, r, g, b, a)
					SUI.Log('Options - Artwork Color changed to r:' .. r .. ' g:' .. g .. ' b:' .. b .. ' a:' .. a, 'Style.Minimal', 'debug')
					SUI.ThemeRegistry:SetSetting('Minimal', 'Color.Art', { r, g, b, a })
					module:SetColor()
				end,
			},
		},
	}
end

function module:OnDisable()
	SUI_Art_Minimal:Hide()
end

function module:SlidingTrays()
	local Settings = {}

	Artwork_Core:SlidingTrays(Settings)
end

function module:SetColor()
	local r, g, b, a

	SUI.Log('SetColor: Starting color update', 'Style.Minimal', 'debug')
	SUI.Log('SetColor: UseClassColors setting = ' .. tostring(SUI.ThemeRegistry:GetSetting('Minimal', 'UseClassColors')), 'Style.Minimal', 'debug')

	if SUI.ThemeRegistry:GetSetting('Minimal', 'UseClassColors') then
		-- Get player class colors
		local _, class = UnitClass('player')
		local classColor = RAID_CLASS_COLORS[class]
		SUI.Log('SetColor: Player class = ' .. tostring(class), 'Style.Minimal', 'debug')
		if classColor then
			r, g, b, a = classColor.r, classColor.g, classColor.b, 1
			SUI.Log('SetColor: Using class colors - r:' .. r .. ' g:' .. g .. ' b:' .. b .. ' a:' .. a, 'Style.Minimal', 'debug')
		else
			-- Fallback to default if class color not found
			local art = SUI.ThemeRegistry:GetSetting('Minimal', 'Color.Art')
			if art then
				r, g, b, a = unpack(art)
			end
			SUI.Log('SetColor: Class color not found, using fallback colors - r:' .. r .. ' g:' .. g .. ' b:' .. b .. ' a:' .. a, 'Style.Minimal', 'debug')
		end
	else
		-- Use custom colors
		local art = SUI.ThemeRegistry:GetSetting('Minimal', 'Color.Art')
		if art then
			r, g, b, a = unpack(art)
		end
		SUI.Log('SetColor: Using custom colors - r:' .. r .. ' g:' .. g .. ' b:' .. b .. ' a:' .. a, 'Style.Minimal', 'debug')
	end

	for i = 1, 5 do
		if _G['SUI_Art_Minimal_Base' .. i] then
			_G['SUI_Art_Minimal_Base' .. i]:SetVertexColor(r, g, b, a)
			SUI.Log('SetColor: Applied color to SUI_Art_Minimal_Base' .. i, 'Style.Minimal', 'debug')
		end
	end

	for _, v in pairs(Artwork_Core.Trays) do
		v.expanded.bg:SetVertexColor(r, g, b, a)
		v.collapsed.bg:SetVertexColor(r, g, b, a)
		SUI.Log('SetColor: Applied color to sliding tray backgrounds', 'Style.Minimal', 'debug')
	end

	SUI.Log('SetColor: Color update complete', 'Style.Minimal', 'debug')
end
