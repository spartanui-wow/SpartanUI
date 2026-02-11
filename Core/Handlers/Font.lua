---@class SUI
local SUI = SUI
local L = SUI.L
local Font = SUI:NewModule('Handler.Font') ---@class SUI.Font | SUI.Module
Font.Items = {}
---@class FontDB
local DBDefaults = {
	Path = '',
	NumberSeperator = nil,
	SetupDone = false,
	Modules = {
		['**'] = {
			Size = 0,
			Face = 'Roboto Bold',
			Type = 'outline',
			Order = 200,
		},
		Global = {
			Order = 1,
		},
		Chatbox = {
			Face = 'Roboto Medium',
		},
	},
}

SUI.Lib.LSM:Register('font', 'Cognosis', [[Interface\AddOns\SpartanUI\fonts\Cognosis.ttf]])
SUI.Lib.LSM:Register('font', 'NotoSans Bold', [[Interface\AddOns\SpartanUI\fonts\NotoSans-Bold.ttf]])
SUI.Lib.LSM:Register('font', 'Roboto Medium', [[Interface\AddOns\SpartanUI\fonts\Roboto-Medium.ttf]])
SUI.Lib.LSM:Register('font', 'Roboto Bold', [[Interface\AddOns\SpartanUI\fonts\Roboto-Bold.ttf]])
SUI.Lib.LSM:Register('font', 'Myriad', [[Interface\AddOns\SpartanUI\fonts\myriad.ttf]])
SUI.Lib.LSM:SetDefault('font', 'Roboto Bold')

---@param value string
---@return string
function Font:comma_value(value)
	local left, num, right = string.match(value, '^([^%d]*%d)(%d*)(.-)$')
	return left .. (num:reverse():gsub('(%d%d%d)', '%1' .. (Font.DB.NumberSeperator or LARGE_NUMBER_SEPERATOR)):reverse()) .. right
end

---@param number any
---@return string
function Font:FormatNumber(number)
	if number >= 1000000 then
		return string.format('%.2fM', number / 1000000)
	elseif number >= 1000 then
		return string.format('%.2fK', number / 1000)
	else
		return tostring(number)
	end
end

---@param element FontString
---@param DefaultSize integer
---@param Module string
function Font:StoreItem(element, DefaultSize, Module)
	--Create tracking table if needed
	if not Font.Items[Module] then
		Font.Items[Module] = { Count = 0 }
	end

	--Load next ID number
	local NewItemID = Font.Items[Module].Count + 1

	--Store element and latest ID used
	Font.Items[Module].Count = NewItemID
	Font.Items[Module][NewItemID .. 'DefaultSize'] = DefaultSize
	Font.Items[Module][NewItemID] = element
end

---@param Module? string
function Font:GetFont(Module)
	if Module and Font.DB and Font.DB.Modules and Font.DB.Modules[Module] then
		return SUI.Lib.LSM:Fetch('font', Font.DB.Modules[Module].Face)
	elseif not Module and Font.DB and Font.DB.Modules and Font.DB.Modules.Global then
		return SUI.Lib.LSM:Fetch('font', Font.DB.Modules.Global.Face)
	end
	return SUI.Lib.LSM:Fetch('font', 'Roboto Bold')
end

---@param element Font
---@param Module string
local function FindID(element, Module)
	for i = 1, Font.Items[Module].Count do
		if Font.Items[Module][i] == element then
			return i
		end
	end
	return false
end

---@param element Font
---@param size integer
---@param Module string
function Font:UpdateDefaultSize(element, size, Module)
	--Update stored default
	local ID = FindID(element, Module)
	if ID then
		--Update the DB
		Font.Items[Module][ID .. 'DefaultSize'] = size
		--Update the screen
		Font:Format(Font.Items[Module][ID], size, Module, true)
	end
end

---@param element FontString
---@param size? integer
---@param Module? string
---@param UpdateOnly? boolean
function Font:Format(element, size, Module, UpdateOnly)
	--If no module defined fall back to main settings
	if not element then
		return
	end
	if not Module then
		Module = 'Global'
	end
	--If we are not initialized yet, save the data for latter processing and exit
	if not Font.DB then
		--Set a default font
		element:SetFont(SUI.Lib.LSM:Fetch('font', 'Roboto Bold'), size or 8, '')
		--Save the data for later
		if not Font.PreLoadItems then
			Font.PreLoadItems = {}
		end
		table.insert(Font.PreLoadItems, { element = element, size = size, Module = Module, UpdateOnly = UpdateOnly })
		return
	end

	-- Ensure Modules table exists (can be nil after profile swap)
	if not Font.DB.Modules then
		Font.DB.Modules = {}
	end

	-- Ensure this specific module entry exists with defaults
	if not Font.DB.Modules[Module] then
		Font.DB.Modules[Module] = {
			Size = 0,
			Face = 'Roboto Bold',
			Type = 'outline',
			Order = 200,
		}
	end

	--Set Font Outline
	local flags, sizeFinal = '', (size or 1)
	if Font.DB.Modules[Module].Type == 'monochrome' then
		flags = flags .. 'monochrome '
	elseif Font.DB.Modules[Module].Type == 'thickoutline' then
		flags = flags .. 'thickoutline '
	elseif Font.DB.Modules[Module].Type == 'outline' then
		element:SetShadowColor(0, 0, 0, 0.9)
		element:SetShadowOffset(1, -1)
	end

	--Set Size
	sizeFinal = size + Font.DB.Modules[Module].Size
	if sizeFinal < 1 then
		sizeFinal = 1
	end

	--Create Font
	element:SetFont(SUI.Font:GetFont(Module), sizeFinal, flags)

	--Store item for latter updating
	if not UpdateOnly then
		Font:StoreItem(element, size, Module)
	end
end

--[[
    Refresh the font settings for the specified module.
    If no module is specified all modules will be updated
]]
---@param Module? string
function Font:Refresh(Module)
	if not Module then
		for key, _ in pairs(Font.Items) do
			Font:Refresh(key)
		end
	else
		for i = 1, Font.Items[Module].Count do
			Font:Format(Font.Items[Module][i], Font.Items[Module][i .. 'DefaultSize'], Module, true)
		end
	end
end

local function FontSetupWizard()
	local function Clear()
		local SUI_Win = SUI.Setup.window
		SUI_Win.FontFace:Hide()
		SUI_Win.FontFace = nil
		Font.DB.SetupDone = true
	end

	local PageData = {
		ID = 'FontSetup',
		name = L['Font style'],
		SubTitle = 'Font Style',
		RequireDisplay = not Font.DB.SetupDone,
		Display = function()
			local SUI_Win = SUI.Setup.window
			SUI_Win.FontFace = CreateFrame('Frame', nil)
			SUI_Win.FontFace:SetParent(SUI.Setup.window.content)
			SUI_Win.FontFace:SetAllPoints(SUI.Setup.window.content)

			local Samples = {}
			Samples[1] = SUI_Win.FontFace:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
			Samples[1].size = 10
			Samples[1]:SetFont(SUI.Font:GetFont(), 10, 'OUTLINE')
			Samples[1]:SetText(
				'Never gonna give you up, never gonna let you down\nNever gonna run around and desert you\nNever gonna make you cry, never gonna say goodbye\nNever gonna tell a lie and hurt you'
			)
			Samples[1]:SetPoint('TOP', SUI_Win.FontFace, 'TOP', 10, -10)
			Samples[1]:SetVertexColor(1, 1, 1)

			Samples[2] = SUI_Win.FontFace:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
			Samples[2].size = 12
			Samples[2]:SetFont(SUI.Font:GetFont(), 12, 'OUTLINE')
			Samples[2]:SetText('The quick brown fox jumps over the lazy dog')
			Samples[2]:SetPoint('TOP', Samples[1], 'BOTTOM', 0, -10)
			Samples[2]:SetVertexColor(1, 1, 1)

			Samples[3] = SUI_Win.FontFace:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
			Samples[3].size = 16
			Samples[3]:SetFont(SUI.Font:GetFont(), 16, 'OUTLINE')
			Samples[3]:SetText('The quick brown fox jumps over the lazy dog')
			Samples[3]:SetPoint('TOP', Samples[2], 'BOTTOM', 0, -10)
			Samples[3]:SetVertexColor(1, 1, 1)

			Samples[4] = SUI_Win.FontFace:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
			Samples[4].size = 18
			Samples[4]:SetFont(SUI.Font:GetFont(), 18, 'OUTLINE')
			Samples[4]:SetText('The quick brown fox jumps over the lazy dog')
			Samples[4]:SetPoint('TOP', Samples[3], 'BOTTOM', 0, -10)
			Samples[4]:SetVertexColor(1, 1, 1)

			SUI_Win.FontFace.Samples = Samples

			---@param font string
			local function SetFont(font)
				for i = 1, #Samples do
					Samples[i]:SetFont(SUI.Lib.LSM:Fetch('font', font), Samples[i].size)
				end
				SUI_Win.FontFace.dropdown:SetValue(font)
			end

			local UI = LibAT.UI
			--Create buttons and position horizontally on the bottom of the window in 2 rows 5 in each row
			SUI_Win.FontFace.FontBtns = {}
			for k, v in ipairs({ 'Cognosis', 'NotoSans Bold', 'Roboto Medium', 'Roboto Bold', 'Myriad', 'Arial Narrow', 'Friz Quadrata TT', '2002' }) do
				--Create Buttons
				local button = UI.CreateButton(SUI_Win.FontFace, 120, 20, v)
				button:SetScript('OnClick', function()
					SetFont(v)
				end)
				-- Set button font to preview the actual font
				local buttonText = button:GetFontString()
				if buttonText then
					buttonText:SetFont(SUI.Lib.LSM:Fetch('font', v), 12)
				end
				--Position Buttons
				if k <= 5 then
					button:SetPoint('TOPLEFT', SUI_Win.FontFace, 'BOTTOMLEFT', 5 + (k - 1) * 130, 120)
				else
					button:SetPoint('TOPLEFT', SUI_Win.FontFace, 'BOTTOMLEFT', 5 + (k - 6) * 130, 70)
				end
				SUI_Win.FontFace.FontBtns[k] = button
			end

			--Create Dropdown for other fonts using AceGUI and LSM30_Font position at the end of the Sample buttons
			local AceGUI = LibStub('AceGUI-3.0')
			local dropdown = AceGUI:Create('LSM30_Font') ---@type AceGUIWidgetLSM30_Font
			dropdown:SetLabel('Other Fonts')
			dropdown:SetList(SUI.Lib.LSM:HashTable('font'))
			dropdown:SetValue('Roboto Bold')
			dropdown:SetCallback('OnValueChanged', function(_, _, value)
				SetFont(value)
			end)
			dropdown.frame:SetParent(SUI_Win.FontFace)
			dropdown.frame:SetPoint('TOPLEFT', SUI_Win.FontFace.FontBtns[#SUI_Win.FontFace.FontBtns], 'TOPRIGHT', 10, 22)
			dropdown.frame:SetWidth(240)
			-- SUI.Skins.RemoveAllTextures(dropdown.frame)
			-- SUI.Skins.SkinObj('Frame', dropdown.frame, 'Dark')
			SUI_Win.FontFace.dropdown = dropdown
		end,
		Next = Clear,
		Skip = Clear,
	}

	SUI.Setup:AddPage(PageData)
end

function Font:OnInitialize()
	Font.Database = SUI.SpartanUIDB:RegisterNamespace('Font', { profile = DBDefaults })
	Font.DB = Font.Database.profile ---@type FontDB

	-- Register for sequential profile refresh with Refresh method
	SUI.DBM:RegisterSequentialProfileRefresh(self, 'Refresh')

	if Font.PreLoadItems then
		--ReRun Font:Format for any fonts that were loaded before the module was enabled
		for k, v in pairs(Font.PreLoadItems) do
			Font:Format(v.element, v.size, v.Module, v.UpdateOnly)
		end
	end
end

function Font:OnEnable()
	FontSetupWizard()
	SUI.opt.args.General.args.Font = {
		name = L['Font'],
		type = 'group',
		order = 200,
		args = {
			Global = {
				type = 'group',
				name = L['Global font settings'],
				order = 0.01,
				inline = true,
				get = function(info)
					return Font.DB.Modules.Global[info[#info]]
				end,
				set = function(info, val)
					Font.DB.Modules.Global[info[#info]] = val
					Font:Refresh()
				end,
				args = {
					Face = {
						type = 'select',
						name = L['Font face'],
						order = 1,
						dialogControl = 'LSM30_Font',
						values = SUI.Lib.LSM:HashTable('font'),
					},
					Type = {
						name = L['Font style'],
						type = 'select',
						order = 2,
						values = {
							['normal'] = L['Normal'],
							['monochrome'] = L['Monochrome'],
							['outline'] = L['Outline'],
							['thickoutline'] = L['Thick outline'],
						},
					},
					Size = {
						name = L['Adjust font size'],
						type = 'range',
						width = 'double',
						min = -3,
						max = 3,
						step = 1,
						order = 3,
					},
					apply = {
						name = L['Apply Global to all'],
						type = 'execute',
						width = 'double',
						order = 50,
						func = function()
							for Module, _ in pairs(Font.Items) do
								Font.DB.Modules[Module].Face = Font.DB.Modules.Global.Face
								Font.DB.Modules[Module].Type = Font.DB.Modules.Global.Type
								Font.DB.Modules[Module].Size = Font.DB.Modules.Global.Size
							end
							Font:Refresh()
						end,
					},
					NumberSeperator = {
						name = L['Large number seperator'],
						desc = L['This is used to split up large numbers example: 100,000'],
						type = 'select',
						get = function(info)
							return Font.DB.NumberSeperator or LARGE_NUMBER_SEPERATOR
						end,
						set = function(info, val)
							Font.DB.NumberSeperator = val
							Font:Refresh()
						end,
						values = { [''] = 'none', [','] = 'comma', ['.'] = 'period', [' '] = 'space' },
					},
				},
			},
		},
	}

	--Setup the Options in 2 seconds giving modules time to populate.
	Font:ScheduleTimer('BuildOptions', 2)
end

function Font:BuildOptions()
	--We build the options based on the modules that are loaded and in use.
	for Module, _ in pairs(Font.Items) do
		if not SUI.opt.args.General.args.Font.args[Module] then
			SUI.opt.args.General.args.Font.args[Module] = {
				name = Module,
				type = 'group',
				order = Font.DB.Modules[Module].Order,
				inline = true,
				get = function(info)
					return Font.DB.Modules[Module][info[#info]]
				end,
				set = function(info, val)
					Font.DB.Modules[Module][info[#info]] = val
					Font:Refresh(Module)
				end,
				args = {
					Face = {
						type = 'select',
						name = L['Font face'],
						order = 1,
						dialogControl = 'LSM30_Font',
						values = SUI.Lib.LSM:HashTable('font'),
					},
					Type = {
						name = L['Font style'],
						type = 'select',
						order = 2,
						values = {
							['normal'] = L['Normal'],
							['monochrome'] = L['Monochrome'],
							['outline'] = L['Outline'],
							['thickoutline'] = L['Thick outline'],
						},
					},
					Size = {
						name = L['Adjust font size'],
						type = 'range',
						order = 3,
						width = 'double',
						min = -15,
						max = 15,
						step = 1,
					},
				},
			}
		end
	end
end

SUI.Font = Font
