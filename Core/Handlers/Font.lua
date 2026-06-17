---@class SUI
local SUI = SUI
local L = SUI.L
local Font = SUI:NewModule('Handler.Font') ---@class SUI.Font | SUI.Module
Font.Items = {}
---@class FontDB
local DBDefaults = {
	Path = '',
	NumberSeperator = nil,
	Modules = {
		['**'] = {
			Size = 0,
			Face = 'Roboto Bold',
			Type = 'normal',
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
			Type = 'normal',
			Order = 200,
		}
	end

	--Set Font Outline
	local flags, sizeFinal = '', (size or 1)
	local fontType = Font.DB.Modules[Module].Type
	if fontType == 'monochrome' then
		flags = 'MONOCHROME'
	elseif fontType == 'thickoutline' then
		flags = 'THICKOUTLINE'
	elseif fontType == 'outline' then
		flags = 'OUTLINE'
	end

	--Set Size
	sizeFinal = size + Font.DB.Modules[Module].Size
	if sizeFinal < 1 then
		sizeFinal = 1
	end

	--Apply the font via a shared FontObject so the drop shadow survives.
	--WoW 12.0: SetShadowColor/SetShadowOffset called directly on a FontString are
	--AllowedWhenUntainted - on unit frame text (which carries secret health/power
	--values) those calls from our tainted code are dropped, so the shadow vanishes.
	--A FontObject carries the shadow as part of its definition, so the string inherits
	--it without a per-string tainted mutation.
	--SetFontObject also overwrites justification with the object's, so preserve the
	--element's own alignment (e.g. left-aligned chat frames) across the swap.
	local justifyH = element.GetJustifyH and element:GetJustifyH()
	local justifyV = element.GetJustifyV and element:GetJustifyV()
	element:SetFontObject(Font:GetFontObject(Module, sizeFinal, flags))
	if justifyH then
		element:SetJustifyH(justifyH)
	end
	if justifyV then
		element:SetJustifyV(justifyV)
	end

	--Store item for latter updating
	if not UpdateOnly then
		Font:StoreItem(element, size, Module)
	end
end

Font.FontObjectCache = {}

--[[
	Return a cached FontObject for the given face/size/flags with SpartanUI's drop
	shadow baked in. FontObjects are created untainted and reused, so the shadow they
	carry is not subject to the WoW 12.0 tainted-FontString shadow restriction that
	strips shadows from unit frame text.
]]
---@param Module? string
---@param size number
---@param flags string
---@return Font
function Font:GetFontObject(Module, size, flags)
	local face = SUI.Font:GetFont(Module)
	local key = tostring(face) .. ':' .. tostring(size) .. ':' .. tostring(flags)
	local fontObject = Font.FontObjectCache[key]
	if not fontObject then
		fontObject = CreateFont('SUIFont_' .. key:gsub('[^%w]', '_'))
		Font.FontObjectCache[key] = fontObject
	end
	fontObject:SetFont(face, size, flags)
	fontObject:SetShadowColor(0, 0, 0, 1)
	fontObject:SetShadowOffset(1, -1)
	return fontObject
end

--[[
	Apply SpartanUI's standard drop shadow to a FontString that is sized outside
	Font:Format (e.g. oUF aura/cast text set with a direct :SetFont()). On secret-
	carrying strings the direct shadow call may be dropped; prefer routing through
	Font:Format / SetFontObject where possible.
]]
---@param element FontString
function Font:ApplyShadow(element)
	if not element or not element.SetShadowColor then
		return
	end
	element:SetShadowColor(0, 0, 0, 1)
	element:SetShadowOffset(1, -1)
end

--[[
    Refresh the font settings for the specified module.
    If no module is specified all modules will be updated
]]
function Font:ReloadDB()
	self:Refresh()
end

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

function Font:OnInitialize()
	Font.Database = SUI.SpartanUIDB:RegisterNamespace('Font', { profile = DBDefaults })
	Font.DB = Font.Database.profile ---@type FontDB

	SUI.DBM:RegisterSequentialProfileRefresh(self)

	if Font.PreLoadItems then
		--ReRun Font:Format for any fonts that were loaded before the module was enabled
		for k, v in pairs(Font.PreLoadItems) do
			Font:Format(v.element, v.size, v.Module, v.UpdateOnly)
		end
	end
end

function Font:OnEnable()
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
