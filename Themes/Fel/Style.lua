local SUI, L = SUI, SUI.L
local print = SUI.print
---@class SUI.Theme.Fel : SUI.Theme.StyleBase
local module = SUI:NewModule('Style.Fel')
---@type SUI.Module
local artFrame = CreateFrame('Frame', 'SUI_Art_Fel', SpartanUI)
module.Settings = {}
----------------------------------------------------------------------------------------------------

local function Options()
	SUI.opt.args.Artwork.args.Fel = {
		name = L['Fel style'],
		type = 'group',
		order = 10,
		args = {
			MinimapEngulfed = {
				name = L['Douse the flames'],
				type = 'toggle',
				order = 0.1,
				desc = L['Is it getting hot in here?'],
				get = function(info)
					return not module.DB.minimap.engulfed
				end,
				set = function(info, val)
					module.DB.minimap.engulfed = not val or false
					module:MiniMap()
				end,
			},
		},
	}
end

function module:OnInitialize()
	---@class SUI.Skins.Fel.Settings
	local defaults = {
		minimap = {
			engulfed = false,
		},
	}
	module.Database = SUI.SpartanUIDB:RegisterNamespace('SkinsFel', { profile = defaults })
	module.DB = module.Database.profile ---@type SUI.Skins.Fel.Settings

	-- Register profile change callbacks
	SUI.DBM:RegisterSequentialProfileRefresh(module)
	-- BarHandler
	local BarHandler = SUI.Handlers.BarSystem
	BarHandler.BarPosition.BT4.Fel = {
		['BT4BarStanceBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-285,175',
		['BT4BarPetBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-607,177',
		['MultiCastActionBarFrame'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,-661,191',
		--
		['BT4BarMicroMenu'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,250,151',
		['BT4BarBagBar'] = 'BOTTOM,SUI_BottomAnchor,BOTTOM,661,174',
	}

	-- Unitframes
	if SUI.UF then
		---@type SUI.Style.Settings.UnitFrames
		local ufsettings = {
			artwork = {
				top = {
					path = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\UnitFrames',
					TexCoord = { 0.1796875, 0.736328125, 0, 0.099609375 },
					heightScale = 0.25,
					yScale = -0.05,
					alpha = 0.8,
				},
				bg = {
					path = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\UnitFrames',
					TexCoord = { 0.02, 0.385, 0.45, 0.575 },
					PVPAlpha = 0.4,
				},
				bottom = {
					path = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\UnitFrames',
					heightScale = 0.115,
					yScale = 0.0158,
					TexCoord = { 0.1796875, 0.736328125, 0.197265625, 0.244140625 },
					PVPAlpha = 0.8,
				},
			},
			displayName = 'Fel',
			setup = {
				image = 'Interface\\AddOns\\SpartanUI\\images\\setup\\Style_Frames_Fel',
			},
		}
		SUI.UF.Style:Register('Fel', ufsettings)
	end

	---@type SUI.Style.Settings.Minimap
	local minimapSettings = SUI.IsRetail
			and {
				-- Retail Fel theme settings (Engulfed variant)
				size = { 180, 180 },
				position = 'CENTER,SUI_Art_Fel_Left,RIGHT,0,-10',
				engulfed = true,
				elements = {
					background = {
						texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Minimap-Engulfed',
						size = { 260, 260 },
						position = 'CENTER,Minimap,CENTER,5,25',
					},
				},
			}
		or {
			-- Classic client Fel theme settings (Engulfed variant)
			size = { 140, 140 },
			position = 'CENTER,SUI_Art_Fel_Left,RIGHT,0,-10',
			engulfed = true,
			background = {
				texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Minimap-Engulfed',
				size = { 220, 220 },
				position = 'CENTER,Minimap,CENTER,5,25',
			},
		}
	SUI.Minimap:Register('Fel', minimapSettings)
	local minimapSettingsCalmed = SUI.IsRetail
			and {
				-- Retail Fel theme settings (Calmed variant)
				size = { 180, 180 },
				position = 'CENTER,SUI_Art_Fel_Left,RIGHT,0,-10',
				engulfed = false,
				elements = {
					background = {
						texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Minimap-Calmed',
						size = { 200, 200 },
						position = 'CENTER,Minimap,CENTER,3,-1',
					},
				},
			}
		or {
			-- Classic client Fel theme settings (Calmed variant)
			size = { 140, 140 },
			position = 'CENTER,SUI_Art_Fel_Left,RIGHT,0,-10',
			engulfed = false,
			background = {
				texture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Minimap-Calmed',
				size = { 162, 162 },
				position = 'CENTER,Minimap,CENTER,3,-1',
			},
		}
	SUI.Minimap:Register('FelCalmed', minimapSettingsCalmed)

	local statusBarModule = SUI:GetModule('Artwork.StatusBars') ---@type SUI.Module.Artwork.StatusBars
	---@type SUI.Style.Settings.StatusBars
	local StatusBarsSettings = {
		bgTexture = 'Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\StatusBar.png',
		alpha = 0.9,
		size = { 370, 20 },
		texCords = { 0.0546875, 0.9140625, 0.5555555555555556, 0 },
		MaxWidth = 48,
	}
	statusBarModule:RegisterStyle('Fel', { Left = SUI:CopyTable({}, StatusBarsSettings), Right = SUI:CopyTable({}, StatusBarsSettings) })

	module:CreateArtwork()
	Options()
end

function module:OnEnable()
	if SUI.DB.Artwork.Style ~= 'Fel' then
		module:Disable()
	else
		module:EnableArtwork()
	end
end

function module:OnDisable()
	artFrame:Hide()
	SUI.opt.args.Artwork.args.Fel.hidden = true
	UnregisterStateDriver(SUI_Art_Fel, 'visibility')
end

function module:SetupVehicleUI()
	if SUI.DB.Artwork.VehicleUI then
		RegisterStateDriver(SUI_Art_Fel, 'visibility', '[overridebar][vehicleui] hide; show')
	end
end

function module:RemoveVehicleUI()
	if SUI.DB.Artwork.VehicleUI then
		UnregisterStateDriver(SUI_Art_Fel, 'visibility')
	end
end

function module:CreateArtwork()
	local plate = CreateFrame('Frame', 'Fel_ActionBarPlate', SpartanUI, 'Fel_ActionBarsTemplate')
	plate:SetFrameStrata('BACKGROUND')
	plate:SetFrameLevel(1)
	plate:ClearAllPoints()
	plate:SetAllPoints(SUI_BottomAnchor)

	--Setup the Bottom Artwork
	artFrame:SetFrameStrata('BACKGROUND')
	artFrame:SetFrameLevel(1)
	artFrame:SetSize(2, 2)
	artFrame:SetPoint('BOTTOM', SUI_BottomAnchor)

	artFrame.Left = artFrame:CreateTexture('SUI_Art_Fel_Left', 'BORDER')
	artFrame.Left:SetPoint('BOTTOMRIGHT', artFrame, 'BOTTOM', 0, 0)
	artFrame.Left:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Base_Bar_Left')

	artFrame.Right = artFrame:CreateTexture('SUI_Art_Fel_Right', 'BORDER')
	artFrame.Right:SetPoint('BOTTOMLEFT', artFrame, 'BOTTOM')
	artFrame.Right:SetTexture('Interface\\AddOns\\SpartanUI\\Themes\\Fel\\Images\\Base_Bar_Right')
end

function module:EnableArtwork()
	hooksecurefunc('UIParent_ManageFramePositions', function()
		if TutorialFrameAlertButton then
			TutorialFrameAlertButton:SetParent(Minimap)
			TutorialFrameAlertButton:ClearAllPoints()
			TutorialFrameAlertButton:SetPoint('CENTER', Minimap, 'TOP', -2, 30)
		end
		if CastingBarFrame then
			CastingBarFrame:ClearAllPoints()
			CastingBarFrame:SetPoint('BOTTOM', SUI_Art_Fel, 'TOP', 0, 90)
		end
	end)

	module:SetupVehicleUI()

	if SUI:IsModuleEnabled('Minimap') then
		module:MiniMap()
	end
end

-- Minimap
function module:MiniMap()
	if module.DB.minimap.engulfed then
		SUI.Minimap:SetActiveStyle('Fel')
	else
		SUI.Minimap:SetActiveStyle('FelCalmed')
	end
end
